import Foundation
import IntervalCore
import Testing
import UserNotifications

@testable import Interval

@MainActor struct NotificationTests {
  @Test func headsUpIsScheduledOneMinuteBeforeFocusEnds() throws {
    let now = Date(timeIntervalSince1970: 1000)
    let timer = TimerState(
      kind: .focus, duration: 1500, status: .running,
      deadline: now.addingTimeInterval(1500))
    let request = try #require(NotificationService.headsUpRequest(timer: timer, now: now))
    let trigger = try #require(request.trigger as? UNTimeIntervalNotificationTrigger)
    #expect(trigger.timeInterval == 1440)
    #expect(!trigger.repeats)
    #expect(request.identifier == timer.id.uuidString + ".heads-up")
  }

  @Test func headsUpExcludesBreaksAndExpiredFocus() {
    let now = Date()
    for kind in [TimerKind.shortBreak, .longBreak] {
      let timer = TimerState(
        kind: kind, duration: 300, status: .running,
        deadline: now.addingTimeInterval(300))
      #expect(NotificationService.headsUpRequest(timer: timer, now: now) == nil)
    }
    let expired = TimerState(kind: .focus, duration: 1500, status: .running, deadline: now)
    #expect(NotificationService.headsUpRequest(timer: expired, now: now) == nil)
    for remaining in [1.0, 30, 60] {
      let timer = TimerState(
        kind: .focus, duration: 1500, status: .running,
        deadline: now.addingTimeInterval(remaining))
      #expect(NotificationService.headsUpRequest(timer: timer, now: now) == nil)
    }
  }

  @Test(arguments: [TimerKind.shortBreak, .longBreak])
  func overdueBreakUsesRepeatingNativeRequest(kind: TimerKind) throws {
    let timer = TimerState(kind: kind, duration: 300, status: .completed)
    let request = try #require(NotificationService.overtimeRequest(timer: timer))
    let trigger = try #require(request.trigger as? UNTimeIntervalNotificationTrigger)
    #expect(trigger.repeats)
    #expect(trigger.timeInterval == 300)
    #expect(request.content.userInfo["timerID"] as? String == timer.id.uuidString)
    #expect(!request.content.categoryIdentifier.isEmpty)
    #expect(request.content.sound != nil)
  }

  @Test func focusAndUnfinishedBreaksDoNotGetOvertimeAlerts() {
    #expect(NotificationService.overtimeRequest(timer: nil) == nil)
    for kind in [TimerKind.focus, .shortBreak, .longBreak] {
      for status in [TimerStatus.ready, .running, .abandoned] {
        #expect(
          NotificationService.overtimeRequest(
            timer: TimerState(kind: kind, duration: 300, status: status)) == nil)
      }
    }
    #expect(
      NotificationService.overtimeRequest(
        timer: TimerState(kind: .focus, duration: 1500, status: .completed)) == nil)
  }
}
