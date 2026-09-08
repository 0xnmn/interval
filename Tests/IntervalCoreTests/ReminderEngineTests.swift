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
    #expect(values.map(\.intervalSeconds) == [600, 1200, 1800, 3600, 300])
    #expect(values.map(\.displaySeconds) == [20, 10, 60, 60, 3])
    #expect(Set(values.map(\.id)).count == 5)
  }

  @Test func shortOverlayPersistsAndCompletesAfterThreeSeconds() throws {
    let blink = Reminder.templates(startingAt: zero).last!
    #expect(blink.presentation == .overlay)
    #expect(blink.clamped().displaySeconds == 3)
    #expect(try JSONDecoder().decode(Reminder.self, from: JSONEncoder().encode(blink)) == blink)
    var short = blink
    short.displaySeconds = 0
    #expect(short.clamped().displaySeconds == 1)
    short.presentation = .fullscreen
    #expect(short.clamped().displaySeconds == 5)
    var values = [blink]
    var engine = ReminderEngine()
    _ = engine.tick(reminders: &values, now: zero.addingTimeInterval(290), environment: .init())
    _ = engine.tick(
      reminders: &values, now: zero.addingTimeInterval(300), environment: .init(idleSeconds: 10))
    #expect(
      engine.overlay == .reminder(reminderID: blink.id, shownAt: zero.addingTimeInterval(300)))
    _ = engine.tick(reminders: &values, now: zero.addingTimeInterval(303), environment: .init())
    #expect(engine.overlay == nil)
    #expect(values[0].effectiveDueAt == zero.addingTimeInterval(600))
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

  @Test func warningIgnoresMouseButPausesForTyping() {
    var values = [reminder()]
    var engine = ReminderEngine()
    func environment(keyboardIdle: TimeInterval) -> ReminderEnvironment {
      .init(isUserIdle: false, idleSeconds: 0, keyboardIdleSeconds: keyboardIdle)
    }
    _ = engine.tick(reminders: &values, now: zero, environment: environment(keyboardIdle: 30))
    _ = engine.tick(
      reminders: &values, now: zero.addingTimeInterval(4),
      environment: environment(keyboardIdle: 34))
    #expect(engine.overlay == .warning(reminderID: values[0].id, remaining: 6, isPaused: false))
    _ = engine.tick(
      reminders: &values, now: zero.addingTimeInterval(8),
      environment: environment(keyboardIdle: 0))
    #expect(engine.overlay == .warning(reminderID: values[0].id, remaining: 6, isPaused: true))
    _ = engine.tick(
      reminders: &values, now: zero.addingTimeInterval(14),
      environment: environment(keyboardIdle: 6))
    #expect(
      engine.overlay == .reminder(reminderID: values[0].id, shownAt: zero.addingTimeInterval(14)))
  }

  @Test func microphoneStillSuppressesKeyboardOnlyWarning() {
    var values = [reminder()]
    var engine = ReminderEngine()
    _ = engine.tick(
      reminders: &values, now: zero,
      environment: .init(isUserIdle: false, idleSeconds: 0, keyboardIdleSeconds: 30))
    #expect(engine.overlay != nil)
    _ = engine.tick(
      reminders: &values, now: zero.addingTimeInterval(1),
      environment: .init(
        isUserIdle: false, idleSeconds: 0, audioInputIsActive: true, keyboardIdleSeconds: 31))
    #expect(engine.overlay == nil)
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
    #expect(value.presentation == .fullscreen)
    #expect(value.sound == .none)
    #expect(value.suppressDuringFocus)
  }

  @Test func displayPreferencesRoundTripAndRespectMinimum() throws {
    let value = Reminder(title: "Stretch", displaySeconds: 1, sound: .glass)
    #expect(value.clamped().displaySeconds == 5)
    let restored = try JSONDecoder().decode(Reminder.self, from: JSONEncoder().encode(value))
    #expect(restored.sound == .glass)
  }

  @Test func whitespaceOnlyTitleClampsToMeaningfulFallback() {
    #expect(Reminder(title: "  \n ").clamped().title == "New reminder")
  }

  @Test func legacyFloatingPositionAndShortDurationMigrateToFullscreen() throws {
    let json = """
      {"title":"Legacy","presentation":"floating","position":"bottomRight","displaySeconds":2}
      """
    let value = try JSONDecoder().decode(Reminder.self, from: Data(json.utf8)).clamped()
    #expect(value.presentation == .fullscreen)
    #expect(value.displaySeconds == 5)
  }
}
