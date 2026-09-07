import Foundation
import Testing

@testable import IntervalCore

struct MeetingSuppressionTests {
  @Test func microphoneSuppressesAllRemindersWithoutCalendarOrFocusOptIn() {
    let start = Date(timeIntervalSince1970: 1000)
    var reminders = (0..<3).map { _ in
      Reminder(
        title: "Break", intervalSeconds: 60, suppressDuringFocus: false,
        suppressDuringCalendar: false, dueAt: start, pauseWhenIdle: true)
    }
    var engine = ReminderEngine()
    let meeting = ReminderEnvironment(idleSeconds: 600, audioInputIsActive: true)
    for minute in 0...30 {
      let now = start.addingTimeInterval(Double(minute * 60))
      #expect(engine.tick(reminders: &reminders, now: now, environment: meeting) == nil)
      #expect(reminders.allSatisfy { $0.effectiveDueAt! > now })
      #expect(reminders.allSatisfy { !engine.canCountDown($0, environment: meeting) })
    }
    #expect(
      engine.tick(
        reminders: &reminders, now: start.addingTimeInterval(1801),
        environment: .init(isUserIdle: false, idleSeconds: 0)) == nil)
  }

  @Test(arguments: [false, true])
  func microphoneClosesExistingWarningOrFullscreen(fullscreen: Bool) {
    let start = Date(timeIntervalSince1970: 1000)
    var reminders = [Reminder(title: "Eyes", dueAt: start.addingTimeInterval(10))]
    var engine = ReminderEngine()
    engine.tick(reminders: &reminders, now: start, environment: .init(idleSeconds: 60))
    if fullscreen {
      engine.tick(
        reminders: &reminders, now: start.addingTimeInterval(10),
        environment: .init(idleSeconds: 70))
      #expect(
        engine.overlay
          == .reminder(
            reminderID: reminders[0].id,
            shownAt: start.addingTimeInterval(10)))
    } else {
      #expect(engine.overlay != nil)
    }
    #expect(
      engine.tick(
        reminders: &reminders, now: start.addingTimeInterval(11),
        environment: .init(idleSeconds: 600, audioInputIsActive: true)) == nil)
  }

  @Test func calendarMeetingSuppressesRemindersWhenMicrophoneIsMuted() {
    let now = Date()
    var reminders = [Reminder(title: "Eyes", dueAt: now)]
    var engine = ReminderEngine()
    let calendarMeeting = ReminderEnvironment(calendarHasEvent: true, idleSeconds: 600)
    #expect(engine.tick(reminders: &reminders, now: now, environment: calendarMeeting) == nil)
    #expect(!engine.canCountDown(reminders[0], environment: calendarMeeting))
    #expect(reminders[0].effectiveDueAt! > now)
  }
}
