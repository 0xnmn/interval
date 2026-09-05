import AppKit
import Foundation
import IntervalCore
import Observation

@MainActor @Observable
final class AppStore {
    var data: PersistedData
    var now = Date()
    var persistenceError: String?
    var recoveryMessage: String?
    var didSave = false
    private let persistence: JSONStore
    private var persistenceLocked = false
    private var ticker: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    init(persistence: JSONStore = JSONStore()) {
        self.persistence = persistence
        var recoveredRunningFocus = false
        do { data = try persistence.load() } catch {
            data = PersistedData()
            persistenceError = "Couldn’t read your saved data. Interval is read-only to protect the original file: \(error.localizedDescription)"
            persistenceLocked = true
        }
        if var restored = data.activeTimer, restored.kind == .focus, restored.status == .running {
            restored.status = .paused
            restored.deadline = nil
            data.activeTimer = restored
            recoveryMessage = "A focus interval was running when Interval closed. It was paused without counting time away."
            recoveredRunningFocus = true
        }
        if data.activeTimer == nil { data.activeTimer = timer(for: .focus) }
        if recoveredRunningFocus { save() }
        reconcile(at: now)
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                self.now = Date(); self.reconcile(at: self.now)
            }
        }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.pauseFocusForSleep() }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in guard let self else { return }; self.now = Date(); self.reconcile(at: self.now) }
        })
    }

    var timer: TimerState { data.activeTimer ?? timer(for: .focus) }
    var remaining: TimeInterval { TimerEngine.remaining(timer, now: now) }
    var suggestedBreak: TimerKind {
        let cadence = max(1, data.settings.longBreakEvery)
        return data.completedFocusCount > 0 && data.completedFocusCount % cadence == 0 ? .longBreak : .shortBreak
    }

    func startOrToggle() {
        let actionDate = Date()
        now = actionDate
        if reconcile(at: actionDate) { return }
        guard var value = data.activeTimer else { return }
        switch value.status {
        case .ready: TimerEngine.start(&value, now: actionDate)
        case .running: TimerEngine.pause(&value, now: actionDate)
        case .paused: TimerEngine.resume(&value, now: actionDate)
        case .completed, .abandoned: return
        }
        data.activeTimer = value; save()
    }

    func abandon() {
        let actionDate = Date()
        now = actionDate
        if reconcile(at: actionDate) { return }
        guard var value = data.activeTimer, value.status == .running || value.status == .paused else { return }
        let activeDuration = TimerEngine.activeDuration(value, now: actionDate)
        TimerEngine.abandon(&value)
        record(value, outcome: .abandoned, endedAt: actionDate, activeDuration: activeDuration)
        data.activeTimer = timer(for: .focus); save()
    }

    func choose(_ kind: TimerKind) {
        guard data.activeTimer?.status == .ready else { return }
        data.activeTimer = timer(for: kind); save()
    }

    func updateScratchpad(_ text: String) { data.scratchpad = text; save() }
    func updateSettings(_ settings: IntervalSettings) {
        data.settings = settings
        if data.activeTimer?.status == .ready { data.activeTimer = timer(for: data.activeTimer?.kind ?? .focus) }
        save()
    }

    private func pauseFocusForSleep() {
        now = Date()
        reconcile(at: now)
        guard var value = data.activeTimer, value.kind == .focus, value.status == .running else { return }
        TimerEngine.pause(&value, now: now); data.activeTimer = value; save()
    }

    @discardableResult private func reconcile(at date: Date) -> Bool {
        guard var value = data.activeTimer else { return false }
        let priorDeadline = value.deadline
        guard TimerEngine.reconcile(&value, now: date) else { return false }
        record(value, outcome: .completed, endedAt: priorDeadline ?? date, activeDuration: value.duration)
        if value.kind == .focus {
            data.completedFocusCount += 1
            data.activeTimer = timer(for: suggestedBreak)
        } else {
            data.activeTimer = timer(for: .focus)
        }
        save()
        return true
    }

    private func record(_ timer: TimerState, outcome: TimerStatus, endedAt: Date, activeDuration: TimeInterval) {
        guard !data.sessions.contains(where: { $0.timerID == timer.id && $0.outcome == outcome }) else { return }
        data.sessions.append(SessionRecord(timerID: timer.id, kind: timer.kind, startedAt: timer.startedAt ?? endedAt,
                                           endedAt: endedAt, plannedDuration: timer.duration,
                                           activeDuration: activeDuration, outcome: outcome))
    }

    private func timer(for kind: TimerKind) -> TimerState { TimerState(kind: kind, duration: data.settings.duration(for: kind)) }
    private func save() {
        guard !persistenceLocked else { return }
        do {
            try persistence.save(data)
            persistenceError = nil
            didSave = true
        } catch {
            persistenceError = "Couldn’t save changes: \(error.localizedDescription)"
            didSave = false
        }
    }
}
