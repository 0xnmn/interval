import Foundation
import IntervalCore
import Testing

@testable import Interval

@MainActor @Suite("Notch heads-up")
struct NotchHeadsUpTests {
  private func candidate(
    _ target: NotchHeadsUp.Target = .focus(UUID()), deadline: Date, eligible: Bool = true
  ) -> NotchHeadsUp {
    NotchHeadsUp(
      target: target, deadline: deadline, title: "Upcoming", symbol: "timer",
      eligible: eligible)
  }

  private func withStore(_ body: (AppStore) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = AppStore(
      persistence: JSONStore(fileURL: directory.appendingPathComponent("data.json")),
      calendarService: CalendarService(fixtureEvents: []), runtimeEnabled: false)
    try body(store)
  }

  @Test func presentationBeginsAtExactlyOneMinute() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let headsUp = candidate(deadline: now.addingTimeInterval(60))
    var state = NotchHeadsUpState()

    state.update([headsUp], at: now.addingTimeInterval(-0.001))
    #expect(state.active == nil)
    state.update([headsUp], at: now)
    #expect(state.active == headsUp)
    #expect(state.expiresAt == now.addingTimeInterval(10))
  }

  @Test func expiryDoesNotReplayTheSameOccurrence() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let headsUp = candidate(deadline: now.addingTimeInterval(60))
    var state = NotchHeadsUpState()

    state.update([headsUp], at: now)
    state.update([headsUp], at: now.addingTimeInterval(10))
    #expect(state.active == nil)
    #expect(state.expiresAt == nil)
    state.update([headsUp], at: now.addingTimeInterval(11))
    #expect(state.active == nil)
  }

  @Test func hoverHoldsPastExpiryUntilReleased() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let headsUp = candidate(deadline: now.addingTimeInterval(60))
    var state = NotchHeadsUpState()

    state.update([headsUp], at: now)
    state.update([headsUp], at: now.addingTimeInterval(20), holding: true)
    #expect(state.active == headsUp)
    #expect(state.expiresAt == now.addingTimeInterval(10))
    state.update([headsUp], at: now.addingTimeInterval(20), holding: false)
    #expect(state.active == nil)
  }

  @Test func explicitDismissDoesNotReplayUntilDeadlineIsRearmed() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let target = NotchHeadsUp.Target.focus(UUID())
    var headsUp = candidate(target, deadline: now.addingTimeInterval(30))
    var state = NotchHeadsUpState()

    state.update([headsUp], at: now)
    state.dismiss()
    state.update([headsUp], at: now.addingTimeInterval(1))
    #expect(state.active == nil)

    headsUp = candidate(target, deadline: now.addingTimeInterval(330))
    state.update([headsUp], at: now.addingTimeInterval(1))
    #expect(state.active == nil)
    state.update([headsUp], at: now.addingTimeInterval(270))
    #expect(state.active == headsUp)
  }

  @Test func simultaneousCandidatesAreQueuedRatherThanDropped() throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let deadline = now.addingTimeInterval(60)
    let candidates = [
      candidate(.focus(UUID()), deadline: deadline),
      candidate(.reminder(UUID()), deadline: deadline),
    ]
    var state = NotchHeadsUpState()

    state.update(candidates, at: now)
    let first = try #require(state.active)
    state.update(candidates, at: now.addingTimeInterval(10))
    let second = try #require(state.active)
    #expect(second.target != first.target)
    state.update(candidates, at: now.addingTimeInterval(20))
    #expect(state.active == nil)
  }

  @Test func removedOrSuppressedCandidateClosesImmediately() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let headsUp = candidate(deadline: now.addingTimeInterval(60))
    var removed = NotchHeadsUpState()
    removed.update([headsUp], at: now)
    removed.update([], at: now.addingTimeInterval(1))
    #expect(removed.active == nil)

    var suppressed = NotchHeadsUpState()
    suppressed.update([headsUp], at: now)
    suppressed.update(
      [candidate(headsUp.target, deadline: headsUp.deadline, eligible: false)],
      at: now.addingTimeInterval(1))
    #expect(suppressed.active == nil)
  }

  @Test func focusActionsRespectExtensionCapAndIgnoreStaleUUID() throws {
    try withStore { store in
      let now = Date()
      store.now = now
      store.data.activeTimer = TimerState(
        kind: .focus, duration: 3_300, status: .running,
        startedAt: now.addingTimeInterval(-3_270), deadline: now.addingTimeInterval(30))
      let headsUp = try #require(store.notchHeadsUpCandidates.first)

      #expect(store.canAdjustHeadsUp(headsUp, minutes: 5))
      #expect(!store.canAdjustHeadsUp(headsUp, minutes: 10))
      store.adjustHeadsUp(headsUp, minutes: 10)
      #expect(store.timer.duration == 3_300)
      store.adjustHeadsUp(headsUp, minutes: 5)
      #expect(store.timer.duration == 3_600)
      #expect(store.timer.deadline == now.addingTimeInterval(330))

      let replacement = TimerState(
        kind: .focus, duration: 1_500, status: .running, startedAt: now,
        deadline: now.addingTimeInterval(1_500))
      store.data.activeTimer = replacement
      #expect(!store.canAdjustHeadsUp(headsUp, minutes: 5))
      store.adjustHeadsUp(headsUp, minutes: 5)
      #expect(store.timer == replacement)
    }
  }

  @Test func reminderActionDelaysOccurrenceWithoutChangingIntervalAndStaleActionIsIgnored() throws {
    try withStore { store in
      let now = Date()
      store.now = now
      let reminder = Reminder(
        title: "Move", intervalSeconds: 1_200, suppressDuringFocus: false,
        suppressDuringCalendar: false, dueAt: now.addingTimeInterval(30))
      store.data.reminders = [reminder]
      let headsUp = try #require(store.notchHeadsUpCandidates.first)

      store.adjustHeadsUp(headsUp, minutes: 5)
      let delayed = try #require(store.data.reminders.first)
      #expect(delayed.intervalSeconds == 1_200)
      #expect(delayed.dueAt == reminder.dueAt)
      #expect(delayed.snoozedUntil == reminder.dueAt?.addingTimeInterval(300))
      #expect(!store.canAdjustHeadsUp(headsUp, minutes: 5))
      store.adjustHeadsUp(headsUp, minutes: 5)
      #expect(store.data.reminders.first == delayed)

      store.data.reminders = []
      #expect(!store.canAdjustHeadsUp(headsUp, minutes: 5))
      store.adjustHeadsUp(headsUp, minutes: 5)
      #expect(store.data.reminders.isEmpty)
    }
  }

  @Test func storeRemovesDisabledReminderAndMarksSuppressedReminderIneligible() throws {
    try withStore { store in
      let due = store.now.addingTimeInterval(30)
      let disabled = Reminder(title: "Disabled", dueAt: due, isEnabled: false)
      let suppressed = Reminder(title: "Suppressed", dueAt: due)
      store.data.reminders = [disabled, suppressed]
      store.reconcileReminders(
        at: store.now,
        environment: .init(isSessionActive: true, calendarHasEvent: true))

      let candidates = store.notchHeadsUpCandidates
      #expect(!candidates.contains { $0.target == .reminder(disabled.id) })
      #expect(candidates.first { $0.target == .reminder(suppressed.id) }?.eligible == false)
    }
  }

  @Test func idleDeadlineDriftDoesNotReplayPresentedOccurrence() throws {
    try withStore { store in
      let start = Date()
      store.now = start
      store.data.reminders = [
        Reminder(
          title: "Eyes", suppressDuringFocus: false,
          suppressDuringCalendar: false, dueAt: start.addingTimeInterval(60),
          pauseWhenIdle: true, idleDelaySeconds: 10)
      ]
      var state = NotchHeadsUpState()
      store.reconcileReminders(at: start, environment: .init(idleSeconds: 0))
      state.update(store.notchHeadsUpCandidates, at: start)
      #expect(state.active != nil)
      for second in 1...30 {
        store.now = start.addingTimeInterval(Double(second))
        store.reconcileReminders(
          at: store.now,
          environment: .init(idleSeconds: Double(second)))
        state.update(store.notchHeadsUpCandidates, at: store.now)
      }
      store.reconcileReminders(at: store.now, environment: .init(isUserIdle: false, idleSeconds: 0))
      state.update(store.notchHeadsUpCandidates, at: store.now)
      #expect(state.active == nil)
    }
  }
}
