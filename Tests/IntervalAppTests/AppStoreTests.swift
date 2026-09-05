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
        #expect(store.timer.status == .ready)
        #expect(store.timer.kind == (count == 4 ? .longBreak : .shortBreak))
        #expect(store.timer.startedAt == nil)
        #expect(store.completionSessionID == store.data.sessions.last?.id)
        #expect(store.data.sessions.count == count * 2 - 1)
        #expect(store.data.sessions.last?.endedAt == deadline)
        #expect(store.data.sessions.last?.activeDuration == 1500)

        store.continueAfterReflection(at: deadline)
        #expect(store.completionSessionID == nil)
        #expect(store.timer.status == .running)
        #expect(store.timer.startedAt == deadline)

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

  @Test func startingRunningSessionIsNoOpAndAbandonDoesNotCount() throws {
    try withStore { store, _ in
      store.startSession()
      let running = store.timer
      store.startSession()
      #expect(store.timer == running)
      store.abandon()
      #expect(store.data.sessions.count == 1)
      #expect(store.data.sessions[0].outcome == .abandoned)
      #expect(store.data.completedFocusCount == 0)
      store.abandon()
      #expect(store.data.sessions.count == 1)
    }
  }

  @Test func lifecycleCheckpointRetainsRunningDeadline() throws {
    try withStore { store, _ in
      for kind in [TimerKind.focus, .shortBreak] {
        let startedAt = Date(timeIntervalSince1970: kind == .focus ? 10_000 : 20_000)
        let duration: TimeInterval = kind == .focus ? 1500 : 300
        store.data.activeTimer = TimerState(
          kind: kind, duration: duration, status: .running, startedAt: startedAt,
          deadline: startedAt.addingTimeInterval(duration))
        let pauseDate = startedAt.addingTimeInterval(30)

        store.checkpointForInactivity(at: pauseDate)

        let checkpointed = store.timer
        #expect(checkpointed.kind == kind)
        #expect(checkpointed.status == .running)
        #expect(checkpointed.elapsedBeforePause == 30)
        #expect(checkpointed.deadline == startedAt.addingTimeInterval(duration))
      }
    }
  }

  @Test func startAtBoundaryCompletesButDoesNotRunNextPhase() throws {
    try withStore { store, _ in
      let deadline = Date().addingTimeInterval(-1)
      store.data.activeTimer = TimerState(
        kind: .focus, duration: 1500, status: .running,
        startedAt: deadline.addingTimeInterval(-1500), deadline: deadline)

      store.startSession()

      #expect(store.data.sessions.count == 1)
      #expect(store.data.sessions[0].outcome == .completed)
      #expect(store.timer.kind == .shortBreak)
      #expect(store.timer.status == .ready)
      #expect(store.timer.elapsedBeforePause == 0)
      #expect(store.completionSessionID == store.data.sessions[0].id)
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
      #expect(store.completionSessionID == nil)
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

  @Test func lateFocusTransitionWaitsForReflectionAndStartsAtContinueDate() throws {
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
      #expect(store.timer.status == .ready)
      #expect(store.timer.startedAt == nil)
      #expect(store.timer.deadline == nil)
      #expect(store.completionSessionID == store.data.sessions[0].id)
      #expect(!store.reconcile(at: observedAt))
      #expect(!store.reconcile(at: observedAt.addingTimeInterval(86_400)))
      #expect(store.data.sessions.count == 1)

      let continuedAt = observedAt.addingTimeInterval(90_000)
      store.continueAfterReflection(at: continuedAt)
      #expect(store.completionSessionID == nil)
      #expect(store.timer.status == .running)
      #expect(store.timer.startedAt == continuedAt)
      #expect(store.timer.deadline == continuedAt.addingTimeInterval(300))

      let startedBreak = store.timer
      store.continueAfterReflection(at: continuedAt.addingTimeInterval(1))
      #expect(store.timer == startedBreak)
    }
  }

  @Test func selectingFeedbackDoesNotStartPendingBreak() throws {
    try withStore { store, _ in
      let deadline = Date(timeIntervalSince1970: 10_000)
      store.data.activeTimer = TimerState(
        kind: .focus, duration: 1500, status: .running,
        startedAt: deadline.addingTimeInterval(-1500), deadline: deadline)
      store.reconcile(at: deadline)
      let sessionID = try #require(store.completionSessionID)

      store.updateSession(id: sessionID, feedback: .focused, journal: "Done")

      #expect(store.completionSessionID == sessionID)
      #expect(store.timer.kind == .shortBreak)
      #expect(store.timer.status == .ready)
    }
  }

  @Test func startSessionCannotBypassPendingReflection() throws {
    try withStore { store, _ in
      let deadline = Date().addingTimeInterval(-1)
      store.data.activeTimer = TimerState(
        kind: .focus, duration: 1500, status: .running,
        startedAt: deadline.addingTimeInterval(-1500), deadline: deadline)
      store.reconcile(at: deadline)
      let sessionID = store.completionSessionID
      store.selection = .history

      store.startSession()

      #expect(store.selection == .focus)
      #expect(store.completionSessionID == sessionID)
      #expect(store.timer.kind == .shortBreak)
      #expect(store.timer.status == .ready)
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

  @Test func todoCRUDPersistsWithoutChangingJournal() throws {
    try withStore { store, persistence in
      let now = Date()
      let session = SessionRecord(
        timerID: UUID(), kind: .focus, startedAt: now.addingTimeInterval(-1500),
        endedAt: now, plannedDuration: 1500, activeDuration: 1500, outcome: .completed)
      store.data.sessions = [session]
      store.data.activeTimer = TimerState(kind: .shortBreak, duration: 300, status: .ready)
      store.completionSessionID = session.id
      store.updateSession(id: session.id, feedback: .focused, journal: "A useful insight")
      #expect(store.completionSessionID == session.id)
      store.addTodo("  First task  ")
      store.addTodo("\n\t")
      store.addTodo("Second task")
      let firstID = try #require(store.data.todos.first?.id)
      let secondID = try #require(store.data.todos.last?.id)
      store.updateTodoTitle(firstID, title: "  Renamed task\n")
      store.updateTodoTitle(firstID, title: "   ")
      store.toggleTodo(firstID)
      #expect(store.data.todos.map(\.id) == [firstID, secondID])
      store.deleteTodo(secondID)
      store.continueAfterReflection(at: now.addingTimeInterval(1))
      let saved = try persistence.load()
      #expect(saved.sessions[0].feedback == "focused")
      #expect(saved.sessions[0].journal == "A useful insight")
      #expect(saved.todos == [TodoItem(id: firstID, title: "Renamed task", isCompleted: true)])
    }
  }

  @Test func restorePendingReflectionDespiteSavedFeedback() throws {
    try withStore { _, persistence in
      let endedAt = Date(timeIntervalSince1970: 10_000)
      let session = SessionRecord(
        timerID: UUID(), kind: .focus, startedAt: endedAt.addingTimeInterval(-1500),
        endedAt: endedAt, plannedDuration: 1500, activeDuration: 1500, outcome: .completed,
        feedback: "focused")
      let breakTimer = TimerState(kind: .shortBreak, duration: 300, status: .ready)
      try persistence.save(PersistedData(activeTimer: breakTimer, sessions: [session]))

      let restored = AppStore(
        persistence: persistence, calendarService: CalendarService(fixtureEvents: []),
        runtimeEnabled: false)

      #expect(restored.completionSessionID == session.id)
    }
  }

  @Test func restoreDoesNotShowOldReflectionDuringActiveFocus() throws {
    try withStore { _, persistence in
      let endedAt = Date(timeIntervalSince1970: 10_000)
      let session = SessionRecord(
        timerID: UUID(), kind: .focus, startedAt: endedAt.addingTimeInterval(-1500),
        endedAt: endedAt, plannedDuration: 1500, activeDuration: 1500, outcome: .completed)
      let focusStart = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970) - 300)
      let activeFocus = TimerState(
        kind: .focus, duration: 1500, status: .running, startedAt: focusStart,
        deadline: focusStart.addingTimeInterval(1500))
      try persistence.save(PersistedData(activeTimer: activeFocus, sessions: [session]))

      let restored = AppStore(
        persistence: persistence, calendarService: CalendarService(fixtureEvents: []),
        runtimeEnabled: false)

      #expect(restored.completionSessionID == nil)
      #expect(restored.timer == activeFocus)
    }
  }

  @Test func restoreExpiredBreakRecordsOnceAndLeavesReadyFocus() throws {
    try withStore { _, persistence in
      let deadline = Date().addingTimeInterval(-10)
      let timer = TimerState(
        kind: .shortBreak, duration: 300, status: .running,
        startedAt: deadline.addingTimeInterval(-300), deadline: deadline)
      try persistence.save(PersistedData(activeTimer: timer))

      let restored = AppStore(
        persistence: persistence, calendarService: CalendarService(fixtureEvents: []),
        runtimeEnabled: false)
      let restoredAgain = AppStore(
        persistence: persistence, calendarService: CalendarService(fixtureEvents: []),
        runtimeEnabled: false)

      #expect(restored.timer.kind == .focus)
      #expect(restored.timer.status == .ready)
      #expect(restored.data.sessions.count == 1)
      #expect(restoredAgain.data.sessions.count == 1)
      #expect(restoredAgain.timer.status == .ready)
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
    store.addTodo("Don't replace the original")
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
      store.startSession()
      let original = store.timer
      var settings = store.data.settings
      settings.focusMinutes = 45
      store.updateSettings(settings)
      #expect(store.timer == original)
      store.abandon()
      #expect(store.timer.duration == 2700)
    }
  }

  @Test func adjustCurrentTimeHandlesReadyAndRunningWithoutChangingSettings() throws {
    try withStore { store, _ in
      let settings = store.data.settings
      let start = Date(timeIntervalSince1970: 10_000)

      store.adjustCurrentTime(by: -10_000, at: start)
      #expect(store.timer.status == .ready)
      #expect(store.timer.duration == 60)

      store.data.activeTimer = TimerState(
        kind: .focus, duration: 1_500, status: .running, startedAt: start,
        deadline: start.addingTimeInterval(1_500))
      store.adjustCurrentTime(by: 300, at: start.addingTimeInterval(100))
      #expect(store.timer.duration == 1_800)
      #expect(store.timer.deadline == start.addingTimeInterval(1_800))
      #expect(TimerEngine.activeDuration(store.timer, now: start.addingTimeInterval(100)) == 100)

      #expect(store.data.settings == settings)
    }
  }

  @Test(
    arguments: [
      (TimerKind.focus, TimeInterval(-300)), (.focus, 300),
      (.shortBreak, -600), (.shortBreak, 600),
      (.longBreak, -900), (.longBreak, 900),
    ])
  func adjustingRunningTimerPreservesElapsedAndShiftsDeadline(
    kind: TimerKind, adjustment: TimeInterval
  ) throws {
    try withStore { store, _ in
      let start = Date(timeIntervalSince1970: 10_000)
      let observedAt = start.addingTimeInterval(120)
      let originalDeadline = start.addingTimeInterval(3_600)
      store.data.activeTimer = TimerState(
        kind: kind, duration: 3_600, status: .running, startedAt: start,
        deadline: originalDeadline)

      store.adjustCurrentTime(by: adjustment, at: observedAt)

      #expect(store.timer.duration == 3_600 + adjustment)
      #expect(store.timer.deadline == originalDeadline.addingTimeInterval(adjustment))
      #expect(TimerEngine.activeDuration(store.timer, now: observedAt) == 120)
    }
  }

  @Test(arguments: [(TimeInterval(-20_000), TimeInterval(60)), (20_000, 10_800)])
  func adjustingRunningTimerClampsRemainingTime(
    adjustment: TimeInterval, expectedRemaining: TimeInterval
  ) throws {
    try withStore { store, _ in
      let start = Date(timeIntervalSince1970: 10_000)
      let observedAt = start.addingTimeInterval(120)
      store.data.activeTimer = TimerState(
        kind: .focus, duration: 1_500, status: .running, startedAt: start,
        deadline: start.addingTimeInterval(1_500))

      store.adjustCurrentTime(by: adjustment, at: observedAt)

      #expect(TimerEngine.remaining(store.timer, now: observedAt) == expectedRemaining)
      #expect(store.timer.duration == 120 + expectedRemaining)
      #expect(TimerEngine.activeDuration(store.timer, now: observedAt) == 120)
    }
  }

  @Test func adjustAtDeadlineCompletesAndDoesNotBypassReflection() throws {
    try withStore { store, _ in
      let deadline = Date(timeIntervalSince1970: 10_000)
      store.data.activeTimer = TimerState(
        kind: .focus, duration: 1_500, status: .running,
        startedAt: deadline.addingTimeInterval(-1_500), deadline: deadline)

      store.adjustCurrentTime(by: 300, at: deadline)

      #expect(store.data.sessions.count == 1)
      #expect(store.completionSessionID == store.data.sessions[0].id)
      #expect(store.timer.kind == .shortBreak)
      #expect(store.timer.status == .ready)
      #expect(store.timer.duration == 300)
    }
  }

  @Test func startBreakNowAccountsForActiveFocusWithoutChangingCadence() throws {
    try withStore { store, _ in
      let start = Date(timeIntervalSince1970: 10_000)
      store.data.completedFocusCount = 3
      store.data.activeTimer = TimerState(
        kind: .focus, duration: 1_500, status: .running, startedAt: start,
        deadline: start.addingTimeInterval(1_500))
      store.startBreakNow(at: start.addingTimeInterval(125))
      #expect(store.data.sessions.count == 1)
      #expect(store.data.sessions[0].outcome == .abandoned)
      #expect(store.data.sessions[0].activeDuration == 125)
      #expect(store.data.completedFocusCount == 3)
      #expect(store.timer.kind == .shortBreak)
      #expect(store.timer.status == .running)

    }
  }

  @Test func endBreakRecordsActualElapsedOnceAndStagesReadyFocus() throws {
    try withStore { store, _ in
      let start = Date(timeIntervalSince1970: 10_000)
      store.data.completedFocusCount = 3
      store.data.activeTimer = TimerState(
        kind: .shortBreak, duration: 300, status: .running, startedAt: start,
        deadline: start.addingTimeInterval(300))

      store.endBreak(at: start.addingTimeInterval(75))
      store.endBreak(at: start.addingTimeInterval(80))

      #expect(store.data.sessions.count == 1)
      #expect(store.data.sessions[0].outcome == .completed)
      #expect(store.data.sessions[0].activeDuration == 75)
      #expect(store.data.completedFocusCount == 3)
      #expect(store.timer.kind == .focus)
      #expect(store.timer.status == .ready)
    }
  }

  @Test func endBreakAtDeadlineRecordsExactlyOnceAndStagesReadyFocus() throws {
    try withStore { store, _ in
      let start = Date(timeIntervalSince1970: 10_000)
      let deadline = start.addingTimeInterval(300)
      store.data.activeTimer = TimerState(
        kind: .shortBreak, duration: 300, status: .running, startedAt: start,
        deadline: deadline)

      store.endBreak(at: deadline)
      store.endBreak(at: deadline)

      #expect(store.data.sessions.count == 1)
      #expect(store.data.sessions[0].kind == .shortBreak)
      #expect(store.data.sessions[0].outcome == .completed)
      #expect(store.data.sessions[0].endedAt == deadline)
      #expect(store.data.sessions[0].activeDuration == 300)
      #expect(store.timer.kind == .focus)
      #expect(store.timer.status == .ready)
    }
  }

  @Test(arguments: [TimerKind.focus, .shortBreak])
  func inactivityReconcilesExpiredTimerWithoutStartingNextPhase(kind: TimerKind) throws {
    try withStore { store, _ in
      let deadline = Date(timeIntervalSince1970: 10_000)
      let duration: TimeInterval = kind == .focus ? 1_500 : 300
      store.data.activeTimer = TimerState(
        kind: kind, duration: duration, status: .running,
        startedAt: deadline.addingTimeInterval(-duration), deadline: deadline)

      store.checkpointForInactivity(at: deadline.addingTimeInterval(60))

      #expect(store.data.sessions.count == 1)
      #expect(store.data.sessions[0].endedAt == deadline)
      #expect(store.timer.status == .ready)
      if kind == .focus {
        #expect(store.timer.kind == .shortBreak)
        #expect(store.completionSessionID == store.data.sessions[0].id)
      } else {
        #expect(store.timer.kind == .focus)
        #expect(store.completionSessionID == nil)
      }
    }
  }

  @Test func legacyPausedRestoreIsAbandonedInsteadOfResumed() throws {
    try withStore { _, persistence in
      let start = Date(timeIntervalSince1970: 10_000)
      let paused = TimerState(
        kind: .focus, duration: 1_500, status: .paused, startedAt: start,
        elapsedBeforePause: 240)
      try persistence.save(PersistedData(activeTimer: paused))

      let restored = AppStore(
        persistence: persistence, calendarService: CalendarService(fixtureEvents: []),
        runtimeEnabled: false)

      #expect(restored.timer.kind == .focus)
      #expect(restored.timer.status == .ready)
      #expect(restored.data.sessions.count == 1)
      #expect(restored.data.sessions[0].outcome == .abandoned)
      #expect(restored.data.sessions[0].activeDuration == 240)
    }
  }

  @Test func readyFocusStartsBreakWithoutRecordAndDeadlineStillRequiresReflection() throws {
    try withStore { store, _ in
      let date = Date(timeIntervalSince1970: 10_000)
      store.data.completedFocusCount = 4
      store.startBreakNow(at: date)
      #expect(store.data.sessions.isEmpty)
      #expect(store.timer.kind == .shortBreak)
      #expect(store.data.completedFocusCount == 4)
      #expect(store.timer.status == .running)
      #expect(store.timer.startedAt == date)

      let deadline = date.addingTimeInterval(2_000)
      store.data.activeTimer = TimerState(
        kind: .focus, duration: 1_500, status: .running,
        startedAt: deadline.addingTimeInterval(-1_500), deadline: deadline)
      store.startBreakNow(at: deadline)
      #expect(store.data.sessions.count == 1)
      #expect(store.data.sessions[0].outcome == .completed)
      #expect(store.completionSessionID == store.data.sessions[0].id)
      #expect(store.timer.kind == .shortBreak)
      #expect(store.timer.status == .ready)
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
      store.addTodo("Portable task")
      let url = persistence.fileURL.deletingLastPathComponent().appendingPathComponent(
        "export.json")
      try store.exportData(to: url)
      let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
      #expect(object?["scratchpad"] == nil)
      let todos = object?["todos"] as? [[String: Any]]
      #expect(todos?.first?["title"] as? String == "Portable task")
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
