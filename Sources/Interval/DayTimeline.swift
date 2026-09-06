import IntervalCore
import SwiftUI

/// A read-only calendar day of saved sessions and Apple Calendar events.
struct DayTimeline: View {
  @Bindable var store: AppStore
  @Binding var selectedSessionID: UUID?
  let date: Date

  private let calendar = Calendar.autoupdatingCurrent
  private let hourHeight: CGFloat = 100
  private let labelWidth: CGFloat = 82
  private let laneSpacing: CGFloat = 4

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if !allDayEvents.isEmpty { allDayRow }
      ScrollViewReader { proxy in
        ScrollView(.vertical) {
          GeometryReader { geometry in
            let timelineWidth = max(geometry.size.width - labelWidth, 0)
            ZStack(alignment: .topLeading) {
              scrollAnchors
              hourGrid(width: timelineWidth)
              if dayInterval.contains(store.now) {
                currentTimeLine(width: timelineWidth)
              }
              ForEach(positionedItems) { item in
                timelineBlock(item, availableWidth: timelineWidth)
              }
            }
          }
          .frame(height: timelineHeight)
        }
        .frame(minHeight: 200)
        .task(id: dayInterval.start) {
          await Task.yield()
          scrollToNow(proxy)
        }
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Timeline for \(date.formatted(date: .complete, time: .omitted))")
  }

  private var allDayRow: some View {
    HStack(alignment: .top, spacing: 8) {
      Text("All day")
        .font(IntervalTheme.body)
        .foregroundStyle(.secondary)
        .frame(width: labelWidth - 8, alignment: .trailing)
        .padding(.top, 5)
      ScrollView(.horizontal) {
        HStack(spacing: 6) {
          ForEach(allDayEvents) { event in
            Label(event.title, systemImage: "calendar")
              .font(.system(size: 14))
              .lineLimit(1)
              .padding(.horizontal, 9)
              .padding(.vertical, 4)
              .foregroundStyle(.blue)
              .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
              .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(.blue.opacity(0.22)) }
              .accessibilityLabel(calendarAccessibilityLabel(event))
          }
        }.padding(.trailing, 10)
      }
      .scrollIndicators(.hidden)
    }
    .padding(.vertical, 7)
    .overlay(alignment: .bottom) { Rectangle().fill(IntervalTheme.border).frame(height: 1) }
  }

  private var scrollAnchors: some View {
    VStack(spacing: 0) {
      ForEach(hourMarks.indices, id: \.self) { index in
        Color.clear.frame(width: 1, height: hourHeight, alignment: .top)
          .id("timeline-hour-\(index)")
      }
    }
  }

  private func hourGrid(width: CGFloat) -> some View {
    ForEach(Array(hourMarks.enumerated()), id: \.offset) { _, mark in
      let y = yPosition(for: mark)
      Text(mark.formatted(date: .omitted, time: .shortened))
        .font(IntervalTheme.body)
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .frame(width: labelWidth - 8, alignment: .trailing)
        .offset(y: y + 3)
      Rectangle()
        .fill(Color.white.opacity(0.075))
        .frame(width: width, height: 1)
        .offset(x: labelWidth, y: y)
    }
  }

  @ViewBuilder
  private func timelineBlock(_ item: PositionedTimelineItem, availableWidth: CGFloat) -> some View {
    let totalSpacing = CGFloat(max(item.laneCount - 1, 0)) * laneSpacing
    let laneWidth = max((availableWidth - totalSpacing) / CGFloat(item.laneCount), 1)
    let x = labelWidth + CGFloat(item.lane) * (laneWidth + laneSpacing)
    let y = yPosition(for: item.start)
    let height = max(yPosition(for: item.end) - y, 24)

    switch item.item {
    case .session(let session):
      Button {
        selectedSessionID = session.id
      } label: {
        blockContents(
          title: session.title?.nilIfEmpty ?? session.kind.title,
          detail: session.categoryName?.nilIfEmpty ?? session.kind.title,
          color: sessionColor(session), height: height)
      }
      .buttonStyle(.plain)
      .accessibilityLabel(sessionAccessibilityLabel(session))
      .frame(width: laneWidth, height: height, alignment: .topLeading)
      .offset(x: x, y: y)
    case .calendar(let event):
      blockContents(
        title: event.title, detail: event.calendarName, color: .blue, height: height
      )
      .opacity(event.status == .canceled || event.status == .declined ? 0.55 : 1)
      .accessibilityLabel(calendarAccessibilityLabel(event))
      .frame(width: laneWidth, height: height, alignment: .topLeading)
      .offset(x: x, y: y)
    }
  }

  private func blockContents(title: String, detail: String, color: Color, height: CGFloat)
    -> some View
  {
    VStack(alignment: .leading, spacing: 1) {
      Text(title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
      if height >= 34 {
        Text(detail).font(.system(size: 14)).lineLimit(1).foregroundStyle(.secondary)
      }
    }
    .padding(.horizontal, 7)
    .padding(.vertical, 4)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .foregroundStyle(.primary)
    .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 6))
    .overlay(alignment: .leading) {
      RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 3).padding(.vertical, 3)
    }
    .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(color.opacity(0.28)) }
    .clipped()
  }

  private func currentTimeLine(width: CGFloat) -> some View {
    let color = store.data.settings.focusColor.color
    let y = yPosition(for: store.now)
    let crossesEvent = positionedItems.contains {
      let start = yPosition(for: $0.start)
      return y >= start && y < max(yPosition(for: $0.end), start + 24)
    }
    return HStack(spacing: 0) {
      Circle().fill(color).frame(width: 7, height: 7)
      Rectangle().fill(color).frame(width: crossesEvent ? 0 : max(width - 3, 0), height: 1)
    }
    .frame(width: width + 4, alignment: .leading)
    .offset(x: labelWidth - 4, y: y - 3)
    .accessibilityLabel("Current time, \(timeText(store.now))")
  }

  private var dayInterval: DateInterval {
    if let interval = calendar.dateInterval(of: .day, for: date) { return interval }
    let start = calendar.startOfDay(for: date)
    let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
    return DateInterval(start: start, end: end)
  }

  private var timelineHeight: CGFloat {
    CGFloat(dayInterval.duration / 3600) * hourHeight
  }

  private var hourMarks: [Date] {
    var marks: [Date] = []
    var mark = dayInterval.start
    while mark < dayInterval.end {
      marks.append(mark)
      guard let next = calendar.date(byAdding: .hour, value: 1, to: mark), next > mark else {
        break
      }
      mark = next
    }
    return marks
  }

  private var allDayEvents: [CalendarEventSnapshot] {
    calendarEvents.filter(\.allDay)
  }

  var calendarEvents: [CalendarEventSnapshot] {
    guard store.calendarService.isEnabled, store.calendarService.authorizationState == .fullAccess
    else { return [] }
    if calendar.isDate(date, inSameDayAs: store.now) {
      return store.calendarService.todayEvents.filter { $0.overlaps(dayInterval) }
    }
    return store.calendarService.events(on: date, calendar: calendar)
  }

  private var positionedItems: [PositionedTimelineItem] {
    var items: [TimelineItem] = store.data.sessions.compactMap { session in
      guard session.startedAt < dayInterval.end, session.endedAt > dayInterval.start else {
        return nil
      }
      return .session(session)
    }
    items +=
      calendarEvents
      .filter { !$0.allDay }
      .map(TimelineItem.calendar)
    return assignLanes(
      items.sorted { lhs, rhs in
        lhs.start == rhs.start ? lhs.end < rhs.end : lhs.start < rhs.start
      })
  }

  private func assignLanes(_ items: [TimelineItem]) -> [PositionedTimelineItem] {
    var result: [PositionedTimelineItem] = []
    var index = 0
    while index < items.count {
      var groupEnd = visualEnd(items[index])
      var groupEndIndex = index + 1
      while groupEndIndex < items.count, items[groupEndIndex].start < groupEnd {
        groupEnd = max(groupEnd, visualEnd(items[groupEndIndex]))
        groupEndIndex += 1
      }

      let group = Array(items[index..<groupEndIndex])
      var laneEnds: [Date] = []
      var assignments: [(TimelineItem, Int)] = []
      for item in group {
        let lane = laneEnds.firstIndex(where: { $0 <= item.start }) ?? laneEnds.count
        if lane == laneEnds.count {
          laneEnds.append(visualEnd(item))
        } else {
          laneEnds[lane] = visualEnd(item)
        }
        assignments.append((item, lane))
      }
      result += assignments.map {
        PositionedTimelineItem(item: $0.0, lane: $0.1, laneCount: max(laneEnds.count, 1))
      }
      index = groupEndIndex
    }
    return result
  }

  private func yPosition(for date: Date) -> CGFloat {
    CGFloat(date.clamped(to: dayInterval).timeIntervalSince(dayInterval.start) / 3600) * hourHeight
  }

  private func visualEnd(_ item: TimelineItem) -> Date {
    max(item.end, max(item.start, dayInterval.start).addingTimeInterval(24 / hourHeight * 3_600))
  }

  private func scrollToNow(_ proxy: ScrollViewProxy) {
    let targetTime =
      calendar.isDate(date, inSameDayAs: store.now)
      ? store.now
      : positionedItems.first?.start ?? calendar.date(
        bySettingHour: 9, minute: 0, second: 0, of: date) ?? date
    let currentIndex = hourMarks.lastIndex(where: { $0 <= targetTime }) ?? 0
    let target = "timeline-hour-\(currentIndex)"
    proxy.scrollTo(target, anchor: .top)
  }

  private func sessionColor(_ session: SessionRecord) -> Color {
    session.kind == .focus
      ? store.data.settings.focusColor.color : store.data.settings.breakColor.color
  }

  private func sessionAccessibilityLabel(_ session: SessionRecord) -> String {
    let title = session.title?.nilIfEmpty ?? session.kind.title
    let category = session.categoryName?.nilIfEmpty.map { ", category \($0)" } ?? ""
    return
      "\(title), \(session.kind.title) session\(category), \(timeRange(session.startedAt, session.endedAt)), \(session.outcome.rawValue)"
  }

  private func calendarAccessibilityLabel(_ event: CalendarEventSnapshot) -> String {
    let time = event.allDay ? "all day" : timeRange(event.start, event.end)
    return
      "\(event.title), Apple Calendar, \(event.calendarName), \(time), \(event.status.rawValue)"
  }

  private func timeRange(_ start: Date, _ end: Date) -> String {
    "\(accessibilityDateTime(start)) to \(accessibilityDateTime(end))"
  }

  private func timeText(_ date: Date) -> String {
    date.formatted(date: .omitted, time: .shortened)
  }

  private func accessibilityDateTime(_ date: Date) -> String {
    date.formatted(date: .abbreviated, time: .shortened)
  }
}

private enum TimelineItem: Identifiable {
  case session(SessionRecord)
  case calendar(CalendarEventSnapshot)

  var id: String {
    switch self {
    case .session(let session): "session-\(session.id)"
    case .calendar(let event): "calendar-\(event.id)"
    }
  }
  var start: Date {
    switch self {
    case .session(let session): session.startedAt
    case .calendar(let event): event.start
    }
  }
  var end: Date {
    switch self {
    case .session(let session): session.endedAt
    case .calendar(let event): event.end
    }
  }
}

private struct PositionedTimelineItem: Identifiable {
  let item: TimelineItem
  let lane: Int
  let laneCount: Int
  var id: String { item.id }
  var start: Date { item.start }
  var end: Date { item.end }
}

extension Date {
  fileprivate func clamped(to interval: DateInterval) -> Date {
    min(max(self, interval.start), interval.end)
  }
}

extension String {
  fileprivate var nilIfEmpty: String? { isEmpty ? nil : self }
}
