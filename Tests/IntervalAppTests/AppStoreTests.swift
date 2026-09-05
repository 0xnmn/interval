import Foundation
import IntervalCore
import Testing

@testable import Interval

@MainActor @Suite("Application workflows")
struct AppStoreTests {
  private func withStore(_ body: (AppStore, JSONStore) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let persistence = JSONStore(fileURL: directory.appendingPathComponent("data.json"))
    let store = AppStore(
      persistence: persistence, calendarService: CalendarService(fixtureEvents: []),
      runtimeEnabled: false)
    try body(store, persistence)
  }

  @Test func fourCompletionsOfferLongBreakExactlyOnce() throws {
    try withStore { store, persistence in
      for count in 1...4 {
        let deadline = Date(timeIntervalSince1970: TimeInterval(count * 10_000))
        store.data.activeTimer = TimerState(
          kind: .focus, duration: 1500, status: .running,
          startedAt: deadline.addingTimeInterval(-1500), deadline: deadline)
        store.reconcile(at: deadline)
        #expect(store.data.completedFocusCount == count)
        #expect(store.timer.status == .running)
        #expect(store.timer.kind == (count == 4 ? .longBreak : .shortBreak))
        #expect(store.timer.startedAt == deadline)
        #expect(store.data.sessions.count == count * 2 - 1)
        #expect(store.data.sessions.last?.endedAt == deadline)
        #expect(store.data.sessions.last?.activeDuration == 1500)

        let breakDeadline = deadline.addingTimeInterval(store.timer.duration)
        store.reconcile(at: breakDeadline)
        #expect(store.timer.status == .running)
        #expect(store.timer.kind == .focus)
        #expect(store.timer.startedAt == breakDeadline)
        #expect(store.data.sessions.count == count * 2)
        #expect(store.data.sessions.last?.kind == (count == 4 ? .longBreak : .shortBreak))
      }
      let saved = try persistence.load()
      #expect(saved.completedFocusCount == 4)
      #expect(saved.sessions.count == 8)
      #expect(saved.settings.longBreakEvery == 4)
      #expect(saved.activeTimer?.kind == .focus)
      #expect(saved.activeTimer?.status == .running)
    }
  }

  @Test func pauseCannotBeOverwrittenAndAbandonDoesNotCount() throws {
    try withStore { store, _ in
      store.startOrToggle()
      let id = store.timer.id
      store.startOrToggle()
      #expect(store.timer.status == .paused)
      #expect(store.timer.id == id)
      store.abandon()
      #expect(store.data.sessions.count == 1)
      #expect(store.data.sessions[0].outcome == .abandoned)
      #expect(store.data.completedFocusCount == 0)
      store.abandon()
      #expect(store.data.sessions.count == 1)
    }
  }

  @Test func lifecyclePausePausesFocusAndBreakWithoutAdvancingLater() throws {
    try withStore { store, _ in
      for kind in [TimerKind.focus, .shortBreak] {
        let startedAt = Date(timeIntervalSince1970: kind == .focus ? 10_000 : 20_000)
        let duration: TimeInterval = kind == .focus ? 1500 : 300
        store.data.activeTimer = TimerState(
          kind: kind, duration: duration, status: .running, startedAt: startedAt,
          deadline: startedAt.addingTimeInterval(duration))
        let pauseDate = startedAt.addingTimeInterval(30)

        store.pauseCycle(at: pauseDate)

        let paused = store.timer
        #expect(paused.kind == kind)
        #expect(paused.status == .paused)
        #expect(paused.elapsedBeforePause == 30)
        #expect(paused.deadline == nil)
        #expect(!store.reconcile(at: startedAt.addingTimeInterval(duration * 10)))
        #expect(store.timer == paused)
        #expect(store.data.sessions.isEmpty)
      }
    }
  }

  @Test func pauseAtBoundaryCompletesButDoesNotRunNextPhase() throws {
    try withStore { store, _ in
      let deadline = Date().addingTimeInterval(-1)
      store.data.activeTimer = TimerState(
        kind: .focus, duration: 1500, status: .running,
        startedAt: deadline.addingTimeInterval(-1500), deadline: deadline)

      store.startOrToggle()

      #expect(store.data.sessions.count == 1)
      #expect(store.data.sessions[0].outcome == .completed)
      #expect(store.timer.kind == .shortBreak)
      #expect(store.timer.status == .paused)
      #expect(store.timer.elapsedBeforePause == 0)
    }
  }

  @Test func abandonAtBoundaryCompletesThenResetsToReadyFocus() throws {
    try withStore { store, _ in
      let deadline = Date().addingTimeInterval(-1)
      store.data.activeTimer = TimerState(
        kind: .focus, duration: 1500, status: .running,
        startedAt: deadline.addingTimeInterval(-1500), deadline: deadline)

      store.abandon()

      #expect(store.data.sessions.count == 1)
      #expect(store.data.sessions[0].outcome == .completed)
      #expect(store.data.completedFocusCount == 1)
      #expect(store.timer.kind == .focus)
      #expect(store.timer.status == .ready)
    }
  }

  @Test func abandoningBreakResetsReadyFocusWithoutChangingCadence() throws {
    try withStore { store, _ in
      store.data.completedFocusCount = 3
      let startedAt = Date().addingTimeInterval(-30)
      store.data.activeTimer = TimerState(
        kind: .longBreak, duration: 600, status: .running, startedAt: startedAt,
        deadline: startedAt.addingTimeInterval(600))

      store.abandon()

      #expect(store.data.completedFocusCount == 3)
      #expect(store.data.sessions.count == 1)
      #expect(store.data.sessions[0].kind == .longBreak)
      #expect(store.data.sessions[0].outcome == .abandoned)
      #expect(store.timer.kind == .focus)
      #expect(store.timer.status == .ready)
    }
  }

  @Test func lateTransitionRecordsOnceAndStartsNextAtObservationDate() throws {
    try withStore { store, _ in
      let deadline = Date(timeIntervalSince1970: 10_000)
      let observedAt = deadline.addingTimeInterval(86_400)
      store.data.activeTimer = TimerState(
        kind: .focus, duration: 1500, status: .running,
        startedAt: deadline.addingTimeInterval(-1500), deadline: deadline)

      #expect(store.reconcile(at: observedAt))
      #expect(store.data.sessions.count == 1)
      #expect(store.data.sessions[0].endedAt == deadline)
      #expect(store.timer.kind == .shortBreak)
      #expect(store.timer.status == .running)
      #expect(store.timer.startedAt == observedAt)
      #expect(store.timer.deadline == observedAt.addingTimeInterval(300))
      #expect(!store.reconcile(at: observedAt))
      #expect(store.data.sessions.count == 1)
    }
  }

  @Test func savingReflectionDoesNotPauseRunningBreak() throws {
    try withStore { store, _ in
      let endedAt = Date(timeIntervalSince1970: 10_000)
      let session = SessionRecord(
        timerID: UUID(), kind: .focus, startedAt: endedAt.addingTimeInterval(-1500),
        endedAt: endedAt, plannedDuration: 1500, activeDuration: 1500, outcome: .completed)
      store.data.sessions = [session]
      let startedAt = endedAt.addingTimeInterval(1)
      store.data.activeTimer = TimerState(
        kind: .shortBreak, duration: 300, status: .running, startedAt: startedAt,
        deadline: startedAt.addingTimeInterval(300))
      let runningBreak = store.timer

      store.updateSession(id: session.id, feedback: .focused, journal: "Done")

      #expect(store.timer == runningBreak)
      #expect(store.data.sessions[0].feedback == "focused")
      #expect(store.data.sessions[0].journal == "Done")
    }
  }

  @Test func reflectionAndScratchpadPersistIndependently() throws {
    try withStore { store, persistence in
      let now = Date()
      let session = SessionRecord(
        timerID: UUID(), kind: .focus, startedAt: now.addingTimeInterval(-1500),
        endedAt: now, plannedDuration: 1500, activeDuration: 1500, outcome: .completed)
      store.data.sessions = [session]
      store.completionSessionID = session.id
      store.updateSession(id: session.id, feedback: .focused, journal: "A useful insight")
      #expect(store.completionSessionID == session.id)
      store.updateScratchpad("Keep this across sessions")
      store.appendQuickNote("Another thought")
      store.deferReflection()
      let saved = try persistence.load()
      #expect(saved.sessions[0].feedback == "focused")
      #expect(saved.sessions[0].journal == "A useful insight")
      #expect(saved.scratchpad == "Keep this across sessions\nAnother thought")
    }
  }

  @Test func corruptPersistenceNeverGetsOverwritten() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("data.json")
    let original = Data("not valid JSON — preserve me".utf8)
    try original.write(to: file)
    let store = AppStore(
      persistence: JSONStore(fileURL: file), calendarService: CalendarService(fixtureEvents: []),
      runtimeEnabled: false)
    #expect(store.persistenceError != nil)
    store.updateScratchpad("Don't replace the original")
    #expect(try Data(contentsOf: file) == original)
    #expect(store.persistenceError != nil)
  }

  @Test func reminderCopiesSnoozeAndUnrelatedDeleteAreIndependent() throws {
    try withStore { store, _ in
      let template = Reminder.templates(startingAt: store.now)[0]
      let first = store.addReminder(template: template)
      let second = store.addReminder(template: template)
      #expect(first != second)
      let anchor = store.data.reminders[0].dueAt
      store.reminderOverlay = .warning(reminderID: first, remaining: 7, isPaused: true)
      store.snoozeReminder(second)
      #expect(store.reminderOverlay?.reminderID == first)
      #expect(store.data.reminders[0].dueAt == anchor)
      #expect(store.data.reminders[1].intervalSeconds == 600)
      #expect(store.data.reminders[1].snoozedUntil != nil)
      store.deleteReminder(second)
      #expect(store.reminderOverlay?.reminderID == first)
    }
  }

  @Test func changingDefaultsDoesNotResizeRunningTimer() throws {
    try withStore { store, _ in
      store.startOrToggle()
      let original = store.timer
      var settings = store.data.settings
      settings.focusMinutes = 45
      store.updateSettings(settings)
      #expect(store.timer == original)
      store.abandon()
      #expect(store.timer.duration == 2700)
    }
  }

  @Test func previewDismissAndPostponeNeverChangeSchedule() throws {
    try withStore { store, _ in
      let id = store.addReminder()
      let before = store.data.reminders
      store.previewReminder(id)
      #expect(store.reminderOverlay?.reminderID == id)
      store.snoozeReminder(id)
      #expect(store.reminderOverlay == nil)
      #expect(store.data.reminders == before)
      store.previewReminder(id)
      store.dismissReminder(id)
      #expect(store.data.reminders == before)
    }
  }

  @Test func exportContainsLocalDataButNoCalendarContents() throws {
    try withStore { store, persistence in
      store.updateScratchpad("Portable note")
      let url = persistence.fileURL.deletingLastPathComponent().appendingPathComponent(
        "export.json")
      try store.exportData(to: url)
      let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
      #expect(object?["scratchpad"] as? String == "Portable note")
      #expect(object?["historyEvents"] == nil)
      #expect(object?["todayEvents"] == nil)
    }
  }

  @Test func selectedCalendarAndMidnightCacheAreIndependentOfHistory() {
    let calendar = Calendar.current
    let midnight = calendar.startOfDay(for: Date())
    let tomorrow = calendar.date(byAdding: .day, value: 1, to: midnight)!
    let work = CalendarEventSnapshot(
      id: "work", title: "Tomorrow", start: tomorrow,
      end: tomorrow.addingTimeInterval(600), allDay: false, calendarName: "Work")
    let personal = CalendarEventSnapshot(
      id: "personal", title: "Today", start: midnight,
      end: tomorrow, allDay: true, calendarName: "Personal")
    let service = CalendarService(fixtureEvents: [work, personal])
    service.configure(enabled: true, selectedCalendarIDs: ["Work"])
    #expect(!service.hasEvent(at: midnight))
    #expect(service.hasEvent(at: tomorrow))
    #expect(!service.hasEvent(at: tomorrow.addingTimeInterval(600)))
    service.show(month: midnight)
    #expect(service.events(on: midnight).isEmpty)
    service.configure(enabled: true, selectedCalendarIDs: [])
    #expect(!service.hasEvent(at: tomorrow))
  }

  @Test func rebuildingMainViewDoesNotResetNavigation() throws {
    try withStore { store, _ in
      store.selection = .history
      _ = MainView(store: store)
      #expect(store.selection == .history)
      store.showFocus()
      #expect(store.selection == .focus)
      #expect(!store.updates.isConfigured)
    }
  }
}
