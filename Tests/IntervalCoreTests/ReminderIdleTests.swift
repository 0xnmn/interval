import Foundation
import Testing

@testable import IntervalCore

@Suite("Reminder idle intervals") struct ReminderIdleTests {
  let zero = Date(timeIntervalSince1970: 1_000)

  func reminder(delay: TimeInterval = 10, enabled: Bool = true) -> Reminder {
    Reminder(
      title: "Look away", intervalSeconds: 600, suppressDuringFocus: false,
      suppressDuringCalendar: false, dueAt: zero.addingTimeInterval(600),
      pauseWhenIdle: enabled, idleDelaySeconds: delay)
  }

  @Test func thresholdPausesOnlyElapsedIdleAndActivityResumes() {
    var values = [reminder(), reminder(delay: 30), reminder(enabled: false)]
    var engine = ReminderEngine()
    for second in [0.0, 9, 10, 20, 40] {
      engine.tick(
        reminders: &values, now: zero.addingTimeInterval(second),
        environment: .init(idleSeconds: second))
      if second <= 10 { #expect(values[0].dueAt == zero.addingTimeInterval(600)) }
    }
    #expect(values.map(\.dueAt) == [630, 610, 600].map { zero.addingTimeInterval($0) })
    engine.tick(
      reminders: &values, now: zero.addingTimeInterval(41),
      environment: .init(isUserIdle: false, idleSeconds: 0))
    #expect(values[0].dueAt == zero.addingTimeInterval(630))
    engine.tick(
      reminders: &values, now: zero.addingTimeInterval(50),
      environment: .init(idleSeconds: 9))
    #expect(values[0].dueAt == zero.addingTimeInterval(630))
    engine.tick(
      reminders: &values, now: zero.addingTimeInterval(53),
      environment: .init(idleSeconds: 12))
    #expect(values[0].dueAt == zero.addingTimeInterval(632))
  }

  @Test func idleDoesNotRetroactivelyCreditBeforeFirstSampleAndPreservesExtensions() {
    var values = [reminder()]
    var engine = ReminderEngine()
    engine.snooze(values[0].id, reminders: &values, now: zero, seconds: 300)
    engine.tick(reminders: &values, now: zero, environment: .init(idleSeconds: 100))
    #expect(values[0].effectiveDueAt == zero.addingTimeInterval(900))
    engine.tick(
      reminders: &values, now: zero.addingTimeInterval(20),
      environment: .init(idleSeconds: 120))
    #expect(values[0].dueAt == zero.addingTimeInterval(620))
    #expect(values[0].snoozedUntil == zero.addingTimeInterval(920))
    #expect(values[0].intervalSeconds == 600)
  }

  @Test func idleCandidateDoesNotBlockOtherRemindersOrFreezeVisibleWarning() {
    var values = [reminder(), reminder(enabled: false)]
    values[0].dueAt = zero.addingTimeInterval(5)
    values[1].dueAt = zero.addingTimeInterval(10)
    var engine = ReminderEngine()
    engine.tick(reminders: &values, now: zero, environment: .init(idleSeconds: 100))
    #expect(engine.overlay?.reminderID == values[1].id)
    engine.tick(
      reminders: &values, now: zero.addingTimeInterval(10),
      environment: .init(idleSeconds: 110))
    #expect(
      engine.overlay == .reminder(reminderID: values[1].id, shownAt: zero.addingTimeInterval(10)))
    #expect(values[0].dueAt == zero.addingTimeInterval(15))

    engine = ReminderEngine()
    values = [reminder()]
    values[0].dueAt = zero.addingTimeInterval(10)
    engine.tick(reminders: &values, now: zero, environment: .init(idleSeconds: 0))
    engine.tick(
      reminders: &values, now: zero.addingTimeInterval(12),
      environment: .init(idleSeconds: 12))
    #expect(
      engine.overlay == .reminder(reminderID: values[0].id, shownAt: zero.addingTimeInterval(12)))
    engine.tick(
      reminders: &values, now: zero.addingTimeInterval(22),
      environment: .init(idleSeconds: 22))
    #expect(engine.overlay == nil)
  }

  @Test func missingIdleTelemetryDoesNotPauseAndDisabledRemindersDoNotMove() {
    var values = [reminder(), reminder()]
    values[1].isEnabled = false
    var engine = ReminderEngine()
    engine.tick(reminders: &values, now: zero, environment: .init())
    engine.tick(reminders: &values, now: zero.addingTimeInterval(40), environment: .init())
    #expect(values.allSatisfy { $0.dueAt == zero.addingTimeInterval(600) })
    engine.tick(
      reminders: &values, now: zero.addingTimeInterval(50),
      environment: .init(idleSeconds: 50))
    #expect(values[1].dueAt == zero.addingTimeInterval(600))
  }

  @Test func preferencesRoundTripAndLegacyRemindersKeepBehavior() throws {
    let original = reminder(delay: 25)
    let restored = try JSONDecoder().decode(Reminder.self, from: JSONEncoder().encode(original))
    #expect(restored == original)
    let legacy = try JSONDecoder().decode(
      Reminder.self, from: Data("{\"title\":\"Look away\"}".utf8))
    #expect(!legacy.pauseWhenIdle)
    #expect(legacy.idleDelaySeconds == 10)
    #expect(Reminder.templates().map(\.pauseWhenIdle) == [true, false, false, false])
    #expect(reminder(delay: .nan).clamped().idleDelaySeconds == 10)
    #expect(reminder(delay: 0).clamped().idleDelaySeconds == 1)
    #expect(reminder(delay: 4_000).clamped().idleDelaySeconds == 3_600)
  }
}
