import Foundation

public enum ReminderOverlay: Equatable, Sendable {
  case warning(reminderID: UUID, remaining: TimeInterval, isPaused: Bool)
  case reminder(reminderID: UUID, shownAt: Date)

  public var reminderID: UUID {
    switch self {
    case .warning(let id, _, _), .reminder(let id, _): id
    }
  }
}

public struct ReminderEnvironment: Equatable, Sendable {
  public var isSessionActive: Bool
  public var isUserIdle: Bool
  public var focusIsRunningOrPaused: Bool
  public var calendarHasEvent: Bool
  public var audioInputIsActive: Bool
  /// Idle duration reported by the OS. Prefer this over inferring idle time between samples.
  public var idleSeconds: TimeInterval?
  /// Keyboard-only idle duration for the final warning; mouse activity must not delay it.
  public var keyboardIdleSeconds: TimeInterval?
  public init(
    isSessionActive: Bool = true, isUserIdle: Bool = true, focusIsRunningOrPaused: Bool = false,
    calendarHasEvent: Bool = false, idleSeconds: TimeInterval? = nil,
    audioInputIsActive: Bool = false, keyboardIdleSeconds: TimeInterval? = nil
  ) {
    self.isSessionActive = isSessionActive
    self.isUserIdle = isUserIdle
    self.focusIsRunningOrPaused = focusIsRunningOrPaused
    self.calendarHasEvent = calendarHasEvent
    self.audioInputIsActive = audioInputIsActive
    self.idleSeconds = idleSeconds
    self.keyboardIdleSeconds = keyboardIdleSeconds
  }
}

/// Pure recurrence/countdown state machine. Callers provide time and environment samples.
public struct ReminderEngine: Equatable, Sendable {
  public private(set) var overlay: ReminderOverlay?
  private var lastTick: Date?
  private var idleCountdown: TimeInterval = 10
  private var priorWasIdle = false

  public init() {}

  @discardableResult public mutating func tick(
    reminders: inout [Reminder], now: Date,
    environment: ReminderEnvironment
  ) -> ReminderOverlay? {
    let sampleGap = max(0, now.timeIntervalSince(lastTick ?? now))
    let warningIdle = environment.keyboardIdleSeconds.map { $0 >= 1 } ?? environment.isUserIdle
    let verifiedIdle: TimeInterval
    if environment.audioInputIsActive {
      verifiedIdle = 0
    } else if let idle = environment.keyboardIdleSeconds ?? environment.idleSeconds {
      verifiedIdle = warningIdle ? min(sampleGap, max(0, idle)) : 0
    } else {
      verifiedIdle = warningIdle && priorWasIdle && sampleGap <= 2 ? sampleGap : 0
    }
    lastTick = now
    priorWasIdle = warningIdle && !environment.audioInputIsActive
    if let visible = overlay,
      !reminders.contains(where: { $0.id == visible.reminderID && $0.isEnabled })
    {
      cancel()
    }
    guard environment.isSessionActive else {
      for index in reminders.indices where reminders[index].isEnabled {
        if let due = reminders[index].effectiveDueAt, due <= now {
          advance(index, reminders: &reminders, now: now)
        }
      }
      cancel()
      return nil
    }

    // Only the repeat interval pauses. A visible warning or reminder must still finish.
    for index in reminders.indices where reminders[index].isEnabled {
      let reminder = reminders[index]
      guard reminder.id != overlay?.reminderID,
        isIdlePaused(reminder, environment),
        let idle = environment.idleSeconds
      else { continue }
      // Charge only the part of this sample after the idle threshold, not the debounce itself.
      let paused = min(sampleGap, max(0, idle - reminder.idleDelaySeconds))
      reminders[index].dueAt = reminder.dueAt?.addingTimeInterval(paused)
      reminders[index].snoozedUntil = reminder.snoozedUntil?.addingTimeInterval(paused)
    }

    if case .reminder(let id, let shownAt) = overlay,
      let reminder = reminders.first(where: { $0.id == id })
    {
      if isSuppressed(reminder, environment) {
        complete(id, reminders: &reminders, now: now)
        return nil
      }
      if now.timeIntervalSince(shownAt) >= reminder.displaySeconds {
        complete(id, reminders: &reminders, now: now)
      }
      return overlay
    }

    if case .warning(let id, _, _) = overlay, let reminder = reminders.first(where: { $0.id == id })
    {
      if isSuppressed(reminder, environment) {
        if now >= (reminder.effectiveDueAt ?? now) {
          complete(id, reminders: &reminders, now: now)
        } else {
          cancel()
        }
        return nil
      }
      idleCountdown = max(0, idleCountdown - verifiedIdle)
      if idleCountdown <= 0 && !isSuppressed(reminder, environment) && warningIdle {
        overlay = .reminder(reminderID: id, shownAt: now)
      } else {
        overlay = .warning(
          reminderID: id, remaining: idleCountdown, isPaused: !warningIdle)
      }
      return overlay
    }

    coalesceMissed(&reminders, now: now, environment: environment)
    guard
      let candidate = reminders.filter({
        $0.effectiveDueAt != nil && canCountDown($0, environment: environment)
      })
      .sorted(by: {
        ($0.effectiveDueAt!, $0.id.uuidString) < ($1.effectiveDueAt!, $1.id.uuidString)
      }).first,
      let due = candidate.effectiveDueAt, now >= due.addingTimeInterval(-10)
    else { return nil }
    // A newly discovered occurrence always receives its complete warning, including after a small delay.
    idleCountdown = 10
    overlay = .warning(
      reminderID: candidate.id, remaining: idleCountdown, isPaused: !warningIdle)
    return overlay
  }

  public mutating func snooze(
    _ id: UUID, reminders: inout [Reminder], now: Date, seconds: TimeInterval = 300
  ) {
    guard let index = reminders.firstIndex(where: { $0.id == id }) else { return }
    let originalDue = reminders[index].effectiveDueAt ?? now
    reminders[index].snoozedUntil = max(now, originalDue).addingTimeInterval(max(1, seconds))
    cancel(reminderID: id)
  }

  public mutating func dismiss(_ id: UUID, reminders: inout [Reminder], now: Date) {
    complete(id, reminders: &reminders, now: now)
  }

  public mutating func cancel() {
    overlay = nil
    idleCountdown = 10
    lastTick = nil
    priorWasIdle = false
  }

  public mutating func cancel(reminderID: UUID) {
    guard overlay?.reminderID == reminderID else { return }
    cancel()
  }

  public func canCountDown(_ reminder: Reminder, environment: ReminderEnvironment) -> Bool {
    reminder.isEnabled && environment.isSessionActive
      && !isSuppressed(reminder, environment) && !isIdlePaused(reminder, environment)
  }

  private func isSuppressed(_ reminder: Reminder, _ environment: ReminderEnvironment) -> Bool {
    environment.audioInputIsActive
      || (reminder.suppressDuringFocus && environment.focusIsRunningOrPaused)
      || (reminder.suppressDuringCalendar && environment.calendarHasEvent)
  }

  private func isIdlePaused(_ reminder: Reminder, _ environment: ReminderEnvironment) -> Bool {
    !environment.audioInputIsActive && reminder.pauseWhenIdle
      && (environment.idleSeconds.map { $0 >= reminder.idleDelaySeconds } ?? false)
  }

  private mutating func complete(_ id: UUID, reminders: inout [Reminder], now: Date) {
    guard let index = reminders.firstIndex(where: { $0.id == id }) else {
      cancel(reminderID: id)
      return
    }
    advance(index, reminders: &reminders, now: now)
    cancel(reminderID: id)
  }

  private func advance(_ index: Int, reminders: inout [Reminder], now: Date) {
    let interval = max(1, reminders[index].intervalSeconds)
    let anchor = reminders[index].dueAt ?? now
    let periods = max(1, floor(now.timeIntervalSince(anchor) / interval) + 1)
    let next = anchor.addingTimeInterval(periods * interval)
    reminders[index].dueAt = next
    reminders[index].snoozedUntil = nil
  }

  private mutating func coalesceMissed(
    _ reminders: inout [Reminder], now: Date, environment: ReminderEnvironment
  ) {
    for index in reminders.indices where reminders[index].isEnabled {
      guard let due = reminders[index].effectiveDueAt, now >= due,
        isSuppressed(reminders[index], environment)
      else { continue }
      advance(index, reminders: &reminders, now: now)
    }
  }
}
