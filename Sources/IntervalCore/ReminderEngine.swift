import Foundation

public enum ReminderOverlay: Equatable, Sendable {
    case warning(reminderID: UUID, remaining: TimeInterval, isPaused: Bool)
    case reminder(reminderID: UUID, shownAt: Date)

    public var reminderID: UUID {
        switch self { case .warning(let id, _, _), .reminder(let id, _): id }
    }
}

public struct ReminderEnvironment: Equatable, Sendable {
    public var isSessionActive: Bool
    public var isUserIdle: Bool
    public var focusIsRunningOrPaused: Bool
    public var calendarHasEvent: Bool
    /// Idle duration reported by the OS. Prefer this over inferring idle time between samples.
    public var idleSeconds: TimeInterval?
    public init(isSessionActive: Bool = true, isUserIdle: Bool = true, focusIsRunningOrPaused: Bool = false,
                calendarHasEvent: Bool = false, idleSeconds: TimeInterval? = nil) {
        self.isSessionActive = isSessionActive; self.isUserIdle = isUserIdle
        self.focusIsRunningOrPaused = focusIsRunningOrPaused; self.calendarHasEvent = calendarHasEvent
        self.idleSeconds = idleSeconds
    }
}

/// Pure recurrence/countdown state machine. Callers provide time and environment samples.
public struct ReminderEngine: Equatable, Sendable {
    public private(set) var overlay: ReminderOverlay?
    private var lastTick: Date?
    private var idleCountdown: TimeInterval = 10
    private var priorWasIdle = false

    public init() {}

    @discardableResult public mutating func tick(reminders: inout [Reminder], now: Date,
                                                  environment: ReminderEnvironment) -> ReminderOverlay? {
        let sampleGap = max(0, now.timeIntervalSince(lastTick ?? now))
        let verifiedIdle: TimeInterval
        if let idle = environment.idleSeconds {
            verifiedIdle = environment.isUserIdle ? min(sampleGap, max(0, idle)) : 0
        } else {
            verifiedIdle = environment.isUserIdle && priorWasIdle && sampleGap <= 2 ? sampleGap : 0
        }
        lastTick = now
        priorWasIdle = environment.isUserIdle
        if let visible = overlay, !reminders.contains(where: { $0.id == visible.reminderID && $0.isEnabled }) { cancel() }
        guard environment.isSessionActive else {
            for index in reminders.indices where reminders[index].isEnabled {
                if let due = reminders[index].effectiveDueAt, due <= now { advance(index, reminders: &reminders, now: now) }
            }
            cancel(); return nil
        }

        if case .reminder(let id, let shownAt) = overlay,
           let reminder = reminders.first(where: { $0.id == id }) {
            if isSuppressed(reminder, environment) { complete(id, reminders: &reminders, now: now); return nil }
            if now.timeIntervalSince(shownAt) >= reminder.displaySeconds { complete(id, reminders: &reminders, now: now) }
            return overlay
        }

        if case .warning(let id, _, _) = overlay, let reminder = reminders.first(where: { $0.id == id }) {
            if isSuppressed(reminder, environment) {
                if now >= (reminder.effectiveDueAt ?? now) { complete(id, reminders: &reminders, now: now) } else { cancel() }
                return nil
            }
            idleCountdown = max(0, idleCountdown - verifiedIdle)
            if idleCountdown <= 0 && !isSuppressed(reminder, environment) && environment.isUserIdle {
                overlay = .reminder(reminderID: id, shownAt: now)
            } else { overlay = .warning(reminderID: id, remaining: idleCountdown, isPaused: !environment.isUserIdle) }
            return overlay
        }

        coalesceMissed(&reminders, now: now, environment: environment)
        guard let candidate = reminders.filter({ $0.isEnabled && $0.effectiveDueAt != nil && !isSuppressed($0, environment) })
            .sorted(by: { ($0.effectiveDueAt!, $0.id.uuidString) < ($1.effectiveDueAt!, $1.id.uuidString) }).first,
              let due = candidate.effectiveDueAt, now >= due.addingTimeInterval(-10) else { return nil }
        // A newly discovered occurrence always receives its complete warning, including after a small delay.
        idleCountdown = 10
        overlay = .warning(reminderID: candidate.id, remaining: idleCountdown, isPaused: !environment.isUserIdle)
        return overlay
    }

    public mutating func snooze(_ id: UUID, reminders: inout [Reminder], now: Date, seconds: TimeInterval = 300) {
        guard let index = reminders.firstIndex(where: { $0.id == id }) else { return }
        reminders[index].snoozedUntil = now.addingTimeInterval(max(1, seconds)); cancel(reminderID: id)
    }

    public mutating func dismiss(_ id: UUID, reminders: inout [Reminder], now: Date) {
        complete(id, reminders: &reminders, now: now)
    }

    public mutating func cancel() { overlay = nil; idleCountdown = 10; lastTick = nil; priorWasIdle = false }

    public mutating func cancel(reminderID: UUID) {
        guard overlay?.reminderID == reminderID else { return }
        cancel()
    }

    private func isSuppressed(_ reminder: Reminder, _ environment: ReminderEnvironment) -> Bool {
        (reminder.suppressDuringFocus && environment.focusIsRunningOrPaused) ||
        (reminder.suppressDuringCalendar && environment.calendarHasEvent)
    }

    private mutating func complete(_ id: UUID, reminders: inout [Reminder], now: Date) {
        guard let index = reminders.firstIndex(where: { $0.id == id }) else { cancel(reminderID: id); return }
        advance(index, reminders: &reminders, now: now); cancel(reminderID: id)
    }

    private func advance(_ index: Int, reminders: inout [Reminder], now: Date) {
        let interval = max(1, reminders[index].intervalSeconds)
        let anchor = reminders[index].dueAt ?? now
        let periods = max(1, floor(now.timeIntervalSince(anchor) / interval) + 1)
        let next = anchor.addingTimeInterval(periods * interval)
        reminders[index].dueAt = next; reminders[index].snoozedUntil = nil
    }

    private mutating func coalesceMissed(_ reminders: inout [Reminder], now: Date, environment: ReminderEnvironment) {
        for index in reminders.indices where reminders[index].isEnabled {
            guard let due = reminders[index].effectiveDueAt, now >= due,
                  isSuppressed(reminders[index], environment) else { continue }
            advance(index, reminders: &reminders, now: now)
        }
    }
}
