import Testing

@testable import Interval

struct DurationFormattingTests {
  @Test func durationRollsIntoHoursAndDays() {
    for (seconds, expected) in [
      (0.0, "00:00"), (-1, "00:00"), (59, "00:59"),
      (60, "01:00"), (3599, "59:59"), (3599.2, "1:00:00"), (3600, "1:00:00"),
      (16509, "4:35:09"), (86399, "23:59:59"), (86400, "1d 00:00:00"),
      (183845, "2d 03:04:05"),
    ] {
      #expect(durationString(seconds) == expected)
    }
  }

  @Test func accessibilityUsesHoursAndDays() {
    #expect(spokenDuration(16509) == "4 hours, 35 minutes, 9 seconds")
    #expect(spokenDuration(90061) == "1 day, 1 hour, 1 minute, 1 second")
    #expect(spokenDuration(0) == "0 seconds")
  }
}
