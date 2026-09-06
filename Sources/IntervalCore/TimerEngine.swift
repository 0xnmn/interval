import Foundation

public enum TimerEngine {
  public static func activeDuration(_ state: TimerState, now: Date) -> TimeInterval {
    switch state.status {
    case .ready: 0
    case .running:
      min(
        state.duration, max(state.elapsedBeforePause, state.duration - remaining(state, now: now)))
    case .paused, .abandoned: min(state.duration, state.elapsedBeforePause)
    case .completed: state.duration
    }
  }

  public static func remaining(_ state: TimerState, now: Date) -> TimeInterval {
    switch state.status {
    case .ready: state.duration
    case .running: max(0, state.deadline?.timeIntervalSince(now) ?? 0)
    case .paused: max(0, state.duration - state.elapsedBeforePause)
    case .completed, .abandoned: 0
    }
  }

  public static func start(_ state: inout TimerState, now: Date) {
    guard state.status == .ready else { return }
    state.duration = min(state.duration, 3_600)
    state.status = .running
    state.startedAt = now
    state.deadline = now.addingTimeInterval(state.duration)
  }

  public static func adjustRemaining(
    _ state: inout TimerState, by seconds: TimeInterval, now: Date,
    minimum: TimeInterval = 60, maximum: TimeInterval = 3_600
  ) {
    guard state.status == .ready || state.status == .running else {
      return
    }
    // A stale hover choice must never add time when subtracting near the deadline.
    if seconds < 0 && remaining(state, now: now) <= minimum { return }
    let elapsed = activeDuration(state, now: now)
    let currentRemaining = remaining(state, now: now)
    // Legacy running timers may already exceed the cap. Preserve their accounting, but do not
    // allow them to grow further. New and in-cap timers are limited by total planned duration.
    if seconds > 0 && state.duration >= maximum { return }
    let maximumRemaining =
      state.duration > maximum ? currentRemaining : max(0, maximum - elapsed)
    let adjustedRemaining = min(
      maximumRemaining, max(minimum, currentRemaining + seconds))
    state.duration = elapsed + adjustedRemaining
    if state.status == .running {
      state.deadline = now.addingTimeInterval(adjustedRemaining)
    }
  }

  public static func abandon(_ state: inout TimerState) {
    guard state.status == .running || state.status == .paused else { return }
    state.status = .abandoned
    state.deadline = nil
  }

  @discardableResult public static func reconcile(_ state: inout TimerState, now: Date) -> Bool {
    guard state.status == .running, let deadline = state.deadline, now >= deadline else {
      return false
    }
    state.status = .completed
    state.deadline = nil
    guard !state.completionRecorded else { return false }
    state.completionRecorded = true
    return true
  }
}
