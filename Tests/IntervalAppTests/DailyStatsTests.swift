import Foundation
import IntervalCore
import Testing

@testable import Interval

@MainActor @Suite("Daily Stats")
struct DailyStatsTests {
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
