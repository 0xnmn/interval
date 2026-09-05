import Foundation

public enum TimerKind: String, Codable, CaseIterable, Sendable {
    case focus, shortBreak, longBreak

    public var title: String {
        switch self { case .focus: "Focus"; case .shortBreak: "Short Break"; case .longBreak: "Long Break" }
    }
}

public enum TimerStatus: String, Codable, Sendable { case ready, running, paused, completed, abandoned }

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

    public init(focusMinutes: Int = 25, shortBreakMinutes: Int = 5, longBreakMinutes: Int = 10, longBreakEvery: Int = 4) {
        self.focusMinutes = focusMinutes; self.shortBreakMinutes = shortBreakMinutes
        self.longBreakMinutes = longBreakMinutes; self.longBreakEvery = longBreakEvery
    }

    public func duration(for kind: TimerKind) -> TimeInterval {
        TimeInterval((kind == .focus ? focusMinutes : kind == .shortBreak ? shortBreakMinutes : longBreakMinutes) * 60)
    }

    public func clamped() -> Self {
        .init(focusMinutes: focusMinutes.clamped(to: 1...180),
              shortBreakMinutes: shortBreakMinutes.clamped(to: 1...60),
              longBreakMinutes: longBreakMinutes.clamped(to: 1...90),
              longBreakEvery: longBreakEvery.clamped(to: 1...12))
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
