import Foundation
import IntervalCore
import Testing

@testable import Interval

@MainActor struct PresentationTests {
  @Test func dialUsesSixtyMinuteScale() {
    #expect(FocusDial.fraction(for: 1_500) == 25.0 / 60)
    #expect(FocusDial.fraction(for: 300) == 5.0 / 60)
    #expect(FocusDial.fraction(for: 3_600) == 1)
    #expect(FocusDial.fraction(for: 0) == 0)
  }

  @Test func reminderCounterUsesActualElapsedTimeAndStopsAtZero() {
    let reminder = Reminder(title: "Look away", displaySeconds: 20, presentation: .fullscreen)
    let start = Date(timeIntervalSince1970: 1_000)
    for (elapsed, expected) in [(0.0, 20), (1, 19), (5.25, 15), (19.9, 1), (20, 0), (30, 0)] {
      #expect(
        ReminderTakeoverView.remainingSeconds(
          reminder: reminder, shownAt: start, now: start.addingTimeInterval(elapsed)) == expected)
    }
  }
}
