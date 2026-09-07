import CoreAudio
import Foundation
import IntervalCore
import Testing

@testable import Interval

@MainActor struct AudioInputActivityTests {
  @Test func nativeInputActivityMetadataIsReadableAndListenersRelease() {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyProcessObjectList,
      mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    #expect(
      AudioObjectGetPropertyDataSize(
        AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr)
    weak var released: AudioInputActivity?
    do {
      let input = AudioInputActivity()
      released = input
      input.start()
      input.start()  // Repeated startup must not leak listeners.
    }
    #expect(released == nil)
  }

  @Test func microphoneSuppressesWarningAndOnlyPostCallIdleCounts() {
    let start = Date(timeIntervalSince1970: 1000)
    let input = AudioInputActivity()
    var reminders = [Reminder(title: "Eyes", dueAt: start.addingTimeInterval(10))]
    var engine = ReminderEngine()
    func environment(at date: Date) -> ReminderEnvironment {
      let idle = input.effectiveIdleSeconds(600, at: date)
      return .init(isUserIdle: idle >= 1, idleSeconds: idle, audioInputIsActive: input.isActive)
    }
    engine.tick(reminders: &reminders, now: start, environment: environment(at: start))
    input.update(isActive: true, at: start)
    let end = start.addingTimeInterval(120)
    engine.tick(reminders: &reminders, now: end, environment: environment(at: end))
    #expect(engine.overlay == nil)
    #expect(reminders[0].effectiveDueAt! > end)
    reminders[0].dueAt = end.addingTimeInterval(10)
    input.update(isActive: false, at: end)
    engine.tick(reminders: &reminders, now: end, environment: environment(at: end))
    #expect(engine.overlay == .warning(reminderID: reminders[0].id, remaining: 10, isPaused: true))
    let resume = end.addingTimeInterval(3)
    engine.tick(reminders: &reminders, now: resume, environment: environment(at: resume))
    #expect(engine.overlay == .warning(reminderID: reminders[0].id, remaining: 7, isPaused: false))
    let show = end.addingTimeInterval(10)
    engine.tick(reminders: &reminders, now: show, environment: environment(at: show))
    #expect(engine.overlay == .reminder(reminderID: reminders[0].id, shownAt: show))
  }

  @Test func audioActivityDoesNotCountAsAwayTimeOrOverrideKeyboardInput() {
    let now = Date(timeIntervalSince1970: 1000)
    let input = AudioInputActivity()
    #expect(input.effectiveIdleSeconds(120, at: now) == 120)
    input.update(isActive: true, at: now)
    #expect(input.effectiveIdleSeconds(600, at: now.addingTimeInterval(300)) == 0)
    input.update(isActive: false, at: now.addingTimeInterval(300))
    #expect(input.effectiveIdleSeconds(600, at: now.addingTimeInterval(305)) == 5)
    #expect(input.effectiveIdleSeconds(0.2, at: now.addingTimeInterval(305)) == 0.2)
    // Repeated inactive notifications must not keep resetting the idle clock.
    input.update(isActive: false, at: now.addingTimeInterval(305))
    #expect(input.effectiveIdleSeconds(600, at: now.addingTimeInterval(312)) == 12)
  }

  @Test func cursorWarningExplainsMicrophoneStandby() {
    let input = AudioInputActivity()
    let reminder = Reminder(title: "Eyes")
    let view = ReminderWarningView(
      reminder: reminder, overlay: .warning(reminderID: reminder.id, remaining: 7, isPaused: false),
      audioInputActivity: input)
    #expect(view.warningStatus == "In 7s")
    input.update(isActive: true, at: Date())
    #expect(view.warningStatus == "Microphone in use")
    input.update(isActive: false, at: Date())
    #expect(view.warningStatus == "In 7s")
  }
}
