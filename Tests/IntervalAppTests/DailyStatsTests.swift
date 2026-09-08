import Foundation
import IntervalCore
import SwiftUI
import Testing

@testable import Interval

@MainActor @Suite("Daily Stats")
struct DailyStatsTests {
  @Test func upcomingRemindersHideSkippedOccurrencesWithoutDeletingThem() {
    let now = SnapshotRenderer.fixtureNow
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let service = CalendarService(fixtureEvents: [
      CalendarEventSnapshot(
        id: "meeting", title: "Meeting", start: now,
        end: now.addingTimeInterval(600), allDay: false, calendarName: "Work")
    ])
    let store = AppStore(
      persistence: JSONStore(fileURL: directory.appendingPathComponent("state.json")),
      calendarService: service, runtimeEnabled: false)
    store.now = now
    service.configure(enabled: true, selectedCalendarIDs: ["Work"])
    _ = service.hasEvent(at: now)
    store.data.activeTimer = TimerState(
      kind: .focus, duration: 1500, status: .running, startedAt: now,
      deadline: now.addingTimeInterval(1500))
    store.data.reminders = [
      Reminder(title: "Focus skipped", suppressDuringCalendar: false, dueAt: now),
      Reminder(title: "Event skipped", suppressDuringFocus: false, dueAt: now),
      Reminder(
        title: "Allowed", suppressDuringFocus: false, suppressDuringCalendar: false, dueAt: now),
      Reminder(title: "After focus", dueAt: now.addingTimeInterval(1800)),
    ]
    #expect(UpcomingReminders(store: store).reminders.map(\.title) == ["Allowed", "After focus"])
    #expect(store.data.reminders.count == 4)
    store.data.activeTimer = nil
    service.configure(enabled: false, selectedCalendarIDs: [])
    #expect(UpcomingReminders(store: store).reminders.count == 4)
  }

  @Test func overviewShowsCurrentAndUpcomingTimedEventsOnly() {
    let now = Calendar.current.date(
      bySettingHour: 12, minute: 0, second: 0, of: SnapshotRenderer.fixtureNow)!
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let service = CalendarService(fixtureEvents: [
      CalendarEventSnapshot(
        id: "past", title: "Finished", start: now.addingTimeInterval(-7200),
        end: now.addingTimeInterval(-3600), allDay: false, calendarName: "Work"),
      CalendarEventSnapshot(
        id: "current", title: "In progress", start: now.addingTimeInterval(-600),
        end: now.addingTimeInterval(600), allDay: false, calendarName: "Work"),
      CalendarEventSnapshot(
        id: "next", title: "Later", start: now.addingTimeInterval(3600),
        end: now.addingTimeInterval(7200), allDay: false, calendarName: "Work"),
      CalendarEventSnapshot(
        id: "all-day", title: "Holiday", start: Calendar.current.startOfDay(for: now),
        end: now.addingTimeInterval(43200), allDay: true, calendarName: "Work"),
    ])
    let store = AppStore(
      persistence: JSONStore(fileURL: directory.appendingPathComponent("state.json")),
      calendarService: service, runtimeEnabled: false)
    store.now = now
    service.configure(enabled: true, selectedCalendarIDs: ["Work"])
    _ = service.hasEvent(at: now)
    #expect(FocusDayPanel(store: store).upcomingEvents.map(\.id) == ["current", "next"])
    service.show(month: now.addingTimeInterval(-86400 * 60))
    #expect(FocusDayPanel(store: store).upcomingEvents.map(\.id) == ["current", "next"])
    #expect(
      DayTimeline(
        store: store, selectedSessionID: .constant(nil), date: now, sessionFilter: { _ in false }
      ).sessions.isEmpty)
  }

  private func loadFixture(_ store: AppStore) {
    store.data = SnapshotRenderer.fixture(scene: "history")
    store.now = Calendar.current.date(
      bySettingHour: 12, minute: 0, second: 0, of: SnapshotRenderer.fixtureNow)!
    let shift = store.now.timeIntervalSince(SnapshotRenderer.fixtureNow)
    for index in store.data.sessions.indices {
      store.data.sessions[index].startedAt.addTimeInterval(shift)
      store.data.sessions[index].endedAt.addTimeInterval(shift)
    }
  }

  @Test func statsSelectedDateScopesTimelineWhileDashboardStaysOnToday() {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let now = SnapshotRenderer.fixtureNow
    let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
    let events = [
      CalendarEventSnapshot(
        id: "previous", title: "Yesterday meeting",
        start: yesterday, end: yesterday.addingTimeInterval(1_800), allDay: false,
        calendarName: "Work")
    ]
    let service = CalendarService(fixtureEvents: events)
    let store = AppStore(
      persistence: JSONStore(fileURL: directory.appendingPathComponent("state.json")),
      calendarService: service, runtimeEnabled: false)
    store.data = SnapshotRenderer.fixture(scene: "history")
    store.now = now
    service.configure(enabled: true, selectedCalendarIDs: ["Work"])
    service.show(month: yesterday)
    _ = service.hasEvent(at: now)
    let timer = store.timer
    let previous = HistoryView(store: store, selectedDate: yesterday)
    #expect(previous.focusDuration == 1_200)
    #expect(FocusDayPanel(store: store).sessions.reduce(0) { $0 + $1.activeDuration } == 4_500)
    let timeline = DayTimeline(store: store, selectedSessionID: .constant(nil), date: yesterday)
    #expect(timeline.calendarEvents.map(\.id) == ["previous"])
    #expect(timeline.sessions.reduce(0) { $0 + $1.activeDuration } == 1_200)
    let filtered = DayTimeline(
      store: store, selectedSessionID: .constant(nil), date: yesterday,
      sessionFilter: { $0.categoryID == store.data.categories[0].id })
    #expect(filtered.sessions.isEmpty)
    #expect(filtered.calendarEvents.map(\.id) == ["previous"])
    #expect(
      DayTimeline(store: store, selectedSessionID: .constant(nil), date: now).calendarEvents.isEmpty
    )
    #expect(store.timer == timer)
  }

  @Test func selectedDayAndCategoryDetermineDistributionsNotLiveTimer() {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = AppStore(
      persistence: JSONStore(fileURL: directory.appendingPathComponent("state.json")),
      runtimeEnabled: false)
    loadFixture(store)
    let currentTimer = store.timer
    let today = HistoryView(store: store)
    #expect(today.focusDuration == 4_500)
    #expect(today.completedFocusCount == 3)
    #expect(today.focusCategoryStats.map(\.duration).sorted() == [1_500, 3_000])
    #expect(today.feedbackStats.first { $0.id == "focused" }?.count == 2)
    #expect(today.feedbackStats.first { $0.id == "neutral" }?.count == 1)

    let filtered = HistoryView(store: store, categoryID: store.data.categories[0].id)
    #expect(filtered.focusDuration == 3_000)
    #expect(filtered.completedFocusCount == 2)
    #expect(filtered.feedbackStats.reduce(0) { $0 + $1.count } == 2)

    let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: store.now)!
    let previous = HistoryView(store: store, selectedDate: yesterday)
    #expect(previous.focusDuration == 1_200)
    #expect(previous.completedFocusCount == 0)
    #expect(previous.feedbackStats.first { $0.id == "distracted" }?.count == 1)
    #expect(store.timer == currentTimer)

    let empty = HistoryView(store: store, selectedDate: store.now.addingTimeInterval(7 * 86_400))
    #expect(empty.focusDuration == 0)
    #expect(empty.feedbackStats.allSatisfy { $0.count == 0 })
  }

  @Test func timelineAndStatsUseSameDayForOvernightSessions() {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = AppStore(
      persistence: JSONStore(fileURL: directory.appendingPathComponent("state.json")),
      runtimeEnabled: false)
    let midnight = Calendar.current.startOfDay(for: SnapshotRenderer.fixtureNow)
    let session = SessionRecord(
      timerID: UUID(), kind: .focus,
      startedAt: midnight.addingTimeInterval(-1500), endedAt: midnight,
      plannedDuration: 1500, activeDuration: 1500, outcome: .completed)
    store.data.sessions = [session]
    for (day, expectedCount) in [(midnight.addingTimeInterval(-3600), 0), (midnight, 1)] {
      let stats = HistoryView(store: store, selectedDate: day)
      let timeline = DayTimeline(
        store: store, selectedSessionID: .constant(nil), date: day,
        sessionFilter: stats.includesSession)
      #expect(stats.completedFocusCount == expectedCount)
      #expect(timeline.sessions.count == expectedCount)
    }
  }

  @Test func unratedIsExplicitAndBreaksNeverCountAsFocusFeedback() {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = AppStore(
      persistence: JSONStore(fileURL: directory.appendingPathComponent("state.json")),
      runtimeEnabled: false)
    loadFixture(store)
    store.data.sessions[0].feedback = nil
    store.data.sessions[1].feedback = "legacy-unknown"
    store.data.sessions[2].kind = .shortBreak
    store.data.sessions[2].feedback = "focused"
    let view = HistoryView(store: store)
    #expect(view.focusDuration == 3_000)
    #expect(view.completedFocusCount == 2)
    #expect(view.feedbackStats.first { $0.id == "unrated" }?.count == 2)
    #expect(view.feedbackStats.first { $0.id == "focused" }?.count == 0)
  }
}
