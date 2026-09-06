import Foundation
import Testing

@testable import IntervalCore

@Suite("Reminder engine") struct ReminderEngineTests {
  let zero = Date(timeIntervalSince1970: 1_000)
  func reminder(due: TimeInterval = 10) -> Reminder {
    Reminder(
      title: "Water", intervalSeconds: 60, displaySeconds: 5, dueAt: zero.addingTimeInterval(due))
  }

  @Test func templatesHaveProductDefaultsAndIndependentIDs() {
    let values = Reminder.templates(startingAt: zero)
    #expect(values.map(\.intervalSeconds) == [600, 1200, 1800, 3600])
    #expect(values.map(\.displaySeconds) == [20, 10, 60, 60])
    #expect(Set(values.map(\.id)).count == 4)
  }

  @Test func activityPausesCountdownAndActualElapsedResumesIt() {
    var values = [reminder()]
    var engine = ReminderEngine()
    _ = engine.tick(reminders: &values, now: zero, environment: .init(isUserIdle: true))
    _ = engine.tick(
      reminders: &values, now: zero.addingTimeInterval(3),
      environment: .init(isUserIdle: true, idleSeconds: 3))
    #expect(engine.overlay == .warning(reminderID: values[0].id, remaining: 7, isPaused: false))
    _ = engine.tick(
      reminders: &values, now: zero.addingTimeInterval(8), environment: .init(isUserIdle: false))
    #expect(engine.overlay == .warning(reminderID: values[0].id, remaining: 7, isPaused: true))
    _ = engine.tick(
      reminders: &values, now: zero.addingTimeInterval(15),
      environment: .init(isUserIdle: true, idleSeconds: 7))
    if case .reminder = engine.overlay {} else { Issue.record("expected full reminder") }
  }

  @Test func snoozeIsRepeatableAndDoesNotMutateAnchor() {
    var values = [reminder()]
    var engine = ReminderEngine()
    let anchor = values[0].dueAt
    engine.snooze(values[0].id, reminders: &values, now: zero, seconds: 300)
    #expect(values[0].dueAt == anchor)
    #expect(values[0].snoozedUntil == zero.addingTimeInterval(310))
    engine.snooze(values[0].id, reminders: &values, now: zero.addingTimeInterval(100), seconds: 300)
    #expect(values[0].snoozedUntil == zero.addingTimeInterval(610))
  }

  @Test func suppressionAndInactiveSessionSkipAndCoalesce() {
    var values = [reminder(due: -125)]
    var engine = ReminderEngine()
    _ = engine.tick(reminders: &values, now: zero, environment: .init(focusIsRunningOrPaused: true))
    #expect(values[0].dueAt == zero.addingTimeInterval(55))
    #expect(engine.overlay == nil)
    values[0].dueAt = zero.addingTimeInterval(-1)
    _ = engine.tick(reminders: &values, now: zero, environment: .init(isSessionActive: false))
    #expect(values[0].dueAt == zero.addingTimeInterval(59))
    #expect(engine.overlay == nil)
  }

  @Test func deterministicEarliestAndNoOverlap() {
    var late = reminder(due: 9)
    late.id = UUID(uuidString: "ffffffff-ffff-ffff-ffff-ffffffffffff")!
    var early = reminder(due: 8)
    early.id = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    var values = [late, early]
    var engine = ReminderEngine()
    _ = engine.tick(reminders: &values, now: zero, environment: .init())
    #expect(engine.overlay?.reminderID == early.id)
  }

  @Test func staleBacklogAdvancesInConstantTimeAndOverdueOccurrenceGetsFullWarning() {
    var stale = reminder(due: -1_000_000_000)
    var engine = ReminderEngine()
    var values = [stale]
    _ = engine.tick(reminders: &values, now: zero, environment: .init(isSessionActive: false))
    #expect(values[0].dueAt! > zero)

    stale = reminder(due: -1)
    values = [stale]
    engine = ReminderEngine()
    _ = engine.tick(
      reminders: &values, now: zero, environment: .init(isUserIdle: true, idleSeconds: 100))
    #expect(engine.overlay == .warning(reminderID: stale.id, remaining: 10, isPaused: false))
  }

  @Test func longSamplingGapDoesNotReceiveUnverifiedIdleCredit() {
    var values = [reminder()]
    var engine = ReminderEngine()
    _ = engine.tick(reminders: &values, now: zero, environment: .init(isUserIdle: true))
    _ = engine.tick(
      reminders: &values, now: zero.addingTimeInterval(5), environment: .init(isUserIdle: true))
    #expect(engine.overlay == .warning(reminderID: values[0].id, remaining: 10, isPaused: false))
  }

  @Test func suppressedEarliestDoesNotBlockEligibleReminder() {
    var suppressed = reminder(due: 2)
    suppressed.suppressDuringFocus = true
    var eligible = reminder(due: 3)
    eligible.suppressDuringFocus = false
    var values = [suppressed, eligible]
    var engine = ReminderEngine()
    _ = engine.tick(reminders: &values, now: zero, environment: .init(focusIsRunningOrPaused: true))
    #expect(engine.overlay?.reminderID == eligible.id)
  }

  @Test func legacyReminderDecodesDefaults() throws {
    let id = UUID()
    let json = "{\"id\":\"\(id)\",\"title\":\"Old\",\"isEnabled\":true}"
    let value = try JSONDecoder().decode(Reminder.self, from: Data(json.utf8))
    #expect(value.message == "Time for a short break.")
    #expect(value.intervalSeconds == 1200)
    #expect(value.presentation == .floating)
    #expect(value.position == .center)
    #expect(value.sound == .none)
    #expect(value.suppressDuringFocus)
  }

  @Test func displayPreferencesRoundTripAndRespectPresentationMinimums() throws {
    var value = Reminder(title: "Stretch", displaySeconds: 1, position: .bottomRight, sound: .glass)
    #expect(value.clamped().displaySeconds == 2)
    value.presentation = .fullscreen
    #expect(value.clamped().displaySeconds == 5)
    let restored = try JSONDecoder().decode(Reminder.self, from: JSONEncoder().encode(value))
    #expect(restored.position == .bottomRight)
    #expect(restored.sound == .glass)
  }

  @Test func twoSecondFloatingReminderFinishesWithoutSkip() {
    var value = reminder()
    value.displaySeconds = 2
    var values = [value.clamped()]
    var engine = ReminderEngine()
    _ = engine.tick(reminders: &values, now: zero, environment: .init())
    _ = engine.tick(
      reminders: &values, now: zero.addingTimeInterval(10),
      environment: .init(idleSeconds: 10))
    #expect(engine.overlay == .reminder(reminderID: value.id, shownAt: zero.addingTimeInterval(10)))
    _ = engine.tick(reminders: &values, now: zero.addingTimeInterval(11.9), environment: .init())
    #expect(engine.overlay != nil)
    _ = engine.tick(reminders: &values, now: zero.addingTimeInterval(12), environment: .init())
    #expect(engine.overlay == nil)
    #expect(values[0].dueAt == zero.addingTimeInterval(70))
    #expect(values[0].intervalSeconds == 60)
  }
}
