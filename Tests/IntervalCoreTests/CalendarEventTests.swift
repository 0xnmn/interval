import Foundation
import Testing

@testable import IntervalCore

struct CalendarEventTests {
  private let calendar: Calendar = {
    var value = Calendar(identifier: .gregorian)
    value.timeZone = TimeZone(secondsFromGMT: 0)!
    return value
  }()

  @Test func overlapUsesHalfOpenBounds() throws {
    let day = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 5)))
    let interval = try #require(CalendarDates.dayInterval(containing: day, calendar: calendar))
    #expect(
      event(start: interval.start.addingTimeInterval(-60), end: interval.start).overlaps(interval)
        == false)
    #expect(
      event(start: interval.end, end: interval.end.addingTimeInterval(60)).overlaps(interval)
        == false)
    #expect(
      event(start: interval.start, end: interval.start.addingTimeInterval(1)).overlaps(interval))
  }

  @Test func allDayMultiDayOverlapsEachCoveredDayOnly() throws {
    let first = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 5)))
    let third = try #require(calendar.date(byAdding: .day, value: 2, to: first))
    let event = event(start: first, end: third, allDay: true)
    #expect(
      event.overlaps(try #require(CalendarDates.dayInterval(containing: first, calendar: calendar)))
    )
    #expect(
      event.overlaps(
        try #require(
          CalendarDates.dayInterval(
            containing: calendar.date(byAdding: .day, value: 1, to: first)!, calendar: calendar))))
    #expect(
      !event.overlaps(
        try #require(CalendarDates.dayInterval(containing: third, calendar: calendar))))
  }

  @Test func canceledAndDeclinedDoNotSuppress() {
    let now = Date()
    #expect(event(start: now, end: now.addingTimeInterval(60)).isEligibleForReminderSuppression)
    #expect(
      !event(start: now, end: now.addingTimeInterval(60), status: .canceled)
        .isEligibleForReminderSuppression)
    #expect(
      !event(start: now, end: now.addingTimeInterval(60), status: .declined)
        .isEligibleForReminderSuppression)
    #expect(
      event(start: now, end: now.addingTimeInterval(60), status: .tentative)
        .isEligibleForReminderSuppression)
  }

  @Test func dayIntervalsFollowSuppliedTimeZone() throws {
    let instant = try #require(ISO8601DateFormatter().date(from: "2026-09-05T01:00:00Z"))
    var pacific = calendar
    pacific.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
    let utcDay = try #require(CalendarDates.dayInterval(containing: instant, calendar: calendar))
    let pacificDay = try #require(CalendarDates.dayInterval(containing: instant, calendar: pacific))
    #expect(utcDay.start != pacificDay.start)
    #expect(utcDay.contains(instant))
    #expect(pacificDay.contains(instant))
  }

  private func event(
    start: Date, end: Date, allDay: Bool = false,
    status: CalendarEventStatus = .confirmed
  ) -> CalendarEventSnapshot {
    CalendarEventSnapshot(
      id: "event", title: "Event", start: start, end: end,
      allDay: allDay, calendarName: "Calendar", status: status)
  }
}
