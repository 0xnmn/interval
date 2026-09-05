import Foundation

public enum TimerKind: String, Codable, CaseIterable, Sendable {
    case focus, shortBreak, longBreak

    public var title: String {
        switch self { case .focus: "Focus"; case .shortBreak: "Short Break"; case .longBreak: "Long Break" }
    }
}

public enum TimerStatus: String, Codable, Sendable { case ready, running, paused, completed, abandoned }

public enum SessionFeedback: String, Codable, CaseIterable, Sendable {
    case distracted, neutral, focused
    public var title: String { rawValue.capitalized }
}

public enum AmbientSound: String, Codable, CaseIterable, Sendable {
    case silence, brownNoise, rain, ocean
    public var title: String {
        switch self { case .silence: "Silence"; case .brownNoise: "Brown Noise"; case .rain: "Rain"; case .ocean: "Ocean" }
    }
}

public struct TimerState: Codable, Equatable, Sendable {
    public var id: UUID
    public var kind: TimerKind
    public var status: TimerStatus
    public var duration: TimeInterval
    public var startedAt: Date?
    public var deadline: Date?
    public var elapsedBeforePause: TimeInterval
    public var completionRecorded: Bool

    public init(id: UUID = UUID(), kind: TimerKind, duration: TimeInterval, status: TimerStatus = .ready,
                startedAt: Date? = nil, deadline: Date? = nil, elapsedBeforePause: TimeInterval = 0,
                completionRecorded: Bool = false) {
        self.id = id; self.kind = kind; self.status = status; self.duration = duration
        self.startedAt = startedAt; self.deadline = deadline; self.elapsedBeforePause = elapsedBeforePause
        self.completionRecorded = completionRecorded
    }
}

public struct IntervalSettings: Codable, Equatable, Sendable {
    public var focusMinutes: Int
    public var shortBreakMinutes: Int
    public var longBreakMinutes: Int
    public var longBreakEvery: Int
    public var focusSound: AmbientSound
    public var breakSound: AmbientSound
    public var soundVolume: Double
    public var calendarIntegrationEnabled: Bool
    public var selectedCalendarIDs: Set<String>
    public var didChooseInitialCalendars: Bool

    public init(focusMinutes: Int = 25, shortBreakMinutes: Int = 5, longBreakMinutes: Int = 10, longBreakEvery: Int = 4,
                focusSound: AmbientSound = .silence, breakSound: AmbientSound = .silence, soundVolume: Double = 0.35,
                calendarIntegrationEnabled: Bool = false, selectedCalendarIDs: Set<String> = [], didChooseInitialCalendars: Bool = false) {
        self.focusMinutes = focusMinutes; self.shortBreakMinutes = shortBreakMinutes
        self.longBreakMinutes = longBreakMinutes; self.longBreakEvery = longBreakEvery
        self.focusSound = focusSound; self.breakSound = breakSound; self.soundVolume = soundVolume
        self.calendarIntegrationEnabled = calendarIntegrationEnabled; self.selectedCalendarIDs = selectedCalendarIDs
        self.didChooseInitialCalendars = didChooseInitialCalendars
    }

    public func duration(for kind: TimerKind) -> TimeInterval {
        TimeInterval((kind == .focus ? focusMinutes : kind == .shortBreak ? shortBreakMinutes : longBreakMinutes) * 60)
    }

    public func clamped() -> Self {
        .init(focusMinutes: focusMinutes.clamped(to: 1...180),
              shortBreakMinutes: shortBreakMinutes.clamped(to: 1...60),
              longBreakMinutes: longBreakMinutes.clamped(to: 1...90),
              longBreakEvery: longBreakEvery.clamped(to: 1...12), focusSound: focusSound, breakSound: breakSound,
              soundVolume: soundVolume.clamped(to: 0...1), calendarIntegrationEnabled: calendarIntegrationEnabled,
              selectedCalendarIDs: selectedCalendarIDs, didChooseInitialCalendars: didChooseInitialCalendars)
    }

    private enum CodingKeys: String, CodingKey { case focusMinutes, shortBreakMinutes, longBreakMinutes, longBreakEvery, focusSound, breakSound, soundVolume, calendarIntegrationEnabled, selectedCalendarIDs, didChooseInitialCalendars }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        focusMinutes = try c.decode(Int.self, forKey: .focusMinutes); shortBreakMinutes = try c.decode(Int.self, forKey: .shortBreakMinutes)
        longBreakMinutes = try c.decode(Int.self, forKey: .longBreakMinutes); longBreakEvery = try c.decode(Int.self, forKey: .longBreakEvery)
        focusSound = try c.decodeIfPresent(AmbientSound.self, forKey: .focusSound) ?? .silence
        breakSound = try c.decodeIfPresent(AmbientSound.self, forKey: .breakSound) ?? .silence
        soundVolume = try c.decodeIfPresent(Double.self, forKey: .soundVolume) ?? 0.35
        calendarIntegrationEnabled = try c.decodeIfPresent(Bool.self, forKey: .calendarIntegrationEnabled) ?? false
        selectedCalendarIDs = try c.decodeIfPresent(Set<String>.self, forKey: .selectedCalendarIDs) ?? []
        didChooseInitialCalendars = try c.decodeIfPresent(Bool.self, forKey: .didChooseInitialCalendars) ?? false
    }
}

public enum CalendarEventStatus: String, Sendable { case confirmed, tentative, canceled, declined }

public struct CalendarEventSnapshot: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let start: Date
    public let end: Date
    public let allDay: Bool
    public let calendarName: String
    public let status: CalendarEventStatus

    public init(id: String, title: String, start: Date, end: Date, allDay: Bool, calendarName: String,
                status: CalendarEventStatus = .confirmed) {
        self.id = id; self.title = title; self.start = start; self.end = end; self.allDay = allDay
        self.calendarName = calendarName; self.status = status
    }

    public var isEligibleForReminderSuppression: Bool { status != .canceled && status != .declined }
    public func overlaps(_ interval: DateInterval) -> Bool {
        start < interval.end && end > interval.start
    }
}

public extension CalendarDates {
    static func dayInterval(containing date: Date, calendar: Calendar) -> DateInterval? {
        calendar.dateInterval(of: .day, for: date)
    }

    static func monthInterval(containing date: Date, calendar: Calendar) -> DateInterval? {
        calendar.dateInterval(of: .month, for: date)
    }
}

public struct SessionRecord: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var timerID: UUID
    public var kind: TimerKind
    public var startedAt: Date
    public var endedAt: Date
    public var plannedDuration: TimeInterval
    public var activeDuration: TimeInterval
    public var outcome: TimerStatus
    public var feedback: String?
    public var journal: String?

    public init(id: UUID = UUID(), timerID: UUID, kind: TimerKind, startedAt: Date, endedAt: Date,
                plannedDuration: TimeInterval, activeDuration: TimeInterval, outcome: TimerStatus, feedback: String? = nil, journal: String? = nil) {
        self.id = id; self.timerID = timerID; self.kind = kind; self.startedAt = startedAt; self.endedAt = endedAt
        self.plannedDuration = plannedDuration; self.activeDuration = activeDuration
        self.outcome = outcome; self.feedback = feedback; self.journal = journal
    }
}

public enum CalendarDates {
    public static func monthGrid(containing date: Date, calendar: Calendar) -> [Date?] {
        guard let month = calendar.dateInterval(of: .month, for: date),
              let days = calendar.range(of: .day, in: .month, for: date) else { return [] }
        let weekday = calendar.component(.weekday, from: month.start)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        var result = Array<Date?>(repeating: nil, count: leading)
        result += days.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: month.start) }.map(Optional.some)
        while result.count % 7 != 0 { result.append(nil) }
        return result
    }

    public static func weekdaySymbols(calendar: Calendar) -> [String] {
        let symbols = calendar.shortStandaloneWeekdaySymbols
        let offset = max(0, min(6, calendar.firstWeekday - 1))
        return Array(symbols[offset...] + symbols[..<offset])
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}

public struct Reminder: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var dueAt: Date?
    public var isEnabled: Bool
    public init(id: UUID = UUID(), title: String, dueAt: Date? = nil, isEnabled: Bool = true) {
        self.id = id; self.title = title; self.dueAt = dueAt; self.isEnabled = isEnabled
    }
}

public struct PersistedData: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    public var version: Int
    public var settings: IntervalSettings
    public var activeTimer: TimerState?
    public var scratchpad: String
    public var sessions: [SessionRecord]
    public var reminders: [Reminder]
    public var completedFocusCount: Int

    public init(version: Int = currentVersion, settings: IntervalSettings = .init(), activeTimer: TimerState? = nil,
                scratchpad: String = "", sessions: [SessionRecord] = [], reminders: [Reminder] = [], completedFocusCount: Int = 0) {
        self.version = version; self.settings = settings; self.activeTimer = activeTimer; self.scratchpad = scratchpad
        self.sessions = sessions; self.reminders = reminders; self.completedFocusCount = completedFocusCount
    }
}
