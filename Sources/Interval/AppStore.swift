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
    var completionSessionID: UUID?
    var inAppNotification: String?
    var audioError: String?
    var notificationError: String?
    let notifications = NotificationService()
    let calendarService: CalendarService
    private let audio = AmbientAudio()
    private let persistence: JSONStore
    private var persistenceLocked = false
    private var ticker: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    init(persistence: JSONStore = JSONStore(), calendarService: CalendarService? = nil) {
        self.persistence = persistence
        self.calendarService = calendarService ?? CalendarService()
        var recoveredRunningFocus = false
        do { data = try persistence.load() } catch {
            data = PersistedData()
            persistenceError = "Couldn’t read your saved data. Interval is read-only to protect the original file: \(error.localizedDescription)"
            persistenceLocked = true
        }
        if var restored = data.activeTimer, restored.kind == .focus, restored.status == .running {
            notifications.cancel(restored)
            restored.status = .paused
            restored.deadline = nil
            data.activeTimer = restored
            recoveryMessage = "A focus interval was running when Interval closed. It was paused without counting time away."
            recoveredRunningFocus = true
        }
        if data.activeTimer == nil { data.activeTimer = timer(for: .focus) }
        self.calendarService.configure(enabled: data.settings.calendarIntegrationEnabled,
                                       selectedCalendarIDs: data.settings.selectedCalendarIDs)
        completionSessionID = data.sessions.last(where: { $0.kind == .focus && $0.outcome == .completed && $0.feedback == nil })?.id
        notifications.fallback = { [weak self] message in self?.inAppNotification = message }
        audio.failure = { [weak self] message in self?.audioError = message }
        if recoveredRunningFocus { save() }
        reconcile(at: now)
        if data.activeTimer?.kind != .focus, data.activeTimer?.status == .running { syncServices(for: timer) }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                self.now = Date(); self.reconcile(at: self.now)
                if Int(self.now.timeIntervalSince1970) % 5 == 0 { self.checkpoint() }
            }
        }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.prepareForSleep() }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.now = Date()
                if !self.reconcile(at: self.now), self.data.activeTimer?.status == .running { self.syncServices(for: self.timer) }
            }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  application.bundleIdentifier == Bundle.main.bundleIdentifier else { return }
            Task { @MainActor in self?.calendarService.applicationDidActivate() }
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
        case .ready:
            inAppNotification = nil
            TimerEngine.start(&value, now: actionDate)
        case .running: TimerEngine.pause(&value, now: actionDate)
        case .paused: TimerEngine.resume(&value, now: actionDate)
        case .completed, .abandoned: return
        }
        data.activeTimer = value; save()
        syncServices(for: value)
    }

    func abandon() {
        let actionDate = Date()
        now = actionDate
        if reconcile(at: actionDate) { return }
        guard var value = data.activeTimer, value.status == .running || value.status == .paused else { return }
        let activeDuration = TimerEngine.activeDuration(value, now: actionDate)
        TimerEngine.abandon(&value)
        notifications.cancel(value); audio.stop()
        record(value, outcome: .abandoned, endedAt: actionDate, activeDuration: activeDuration)
        data.activeTimer = timer(for: .focus); save()
    }

    func choose(_ kind: TimerKind) {
        guard data.activeTimer?.status == .ready else { return }
        data.activeTimer = timer(for: kind); save()
    }

    func updateScratchpad(_ text: String) { data.scratchpad = text; save() }
    func appendQuickNote(_ text: String) { guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }; data.scratchpad += (data.scratchpad.isEmpty ? "" : "\n") + text; save() }
    func updateSession(id: UUID, feedback: SessionFeedback?, journal: String) {
        guard let index = data.sessions.firstIndex(where: { $0.id == id }) else { return }
        data.sessions[index].feedback = feedback?.rawValue; data.sessions[index].journal = journal.isEmpty ? nil : journal; save()
    }
    func deferReflection() { completionSessionID = nil }
    func updateSettings(_ settings: IntervalSettings) {
        data.settings = settings
        if data.activeTimer?.status == .ready { data.activeTimer = timer(for: data.activeTimer?.kind ?? .focus) }
        save()
        if data.activeTimer?.status == .running { syncServices(for: timer) }
    }

    func enableCalendarIntegration() async {
        guard await calendarService.requestFullAccessToEvents() else { return }
        var settings = data.settings
        settings.calendarIntegrationEnabled = true
        if !settings.didChooseInitialCalendars {
            settings.selectedCalendarIDs = Set(calendarService.calendars.map(\.id))
            settings.didChooseInitialCalendars = true
        }
        updateCalendarSettings(settings)
    }

    func disableCalendarIntegration() {
        var settings = data.settings; settings.calendarIntegrationEnabled = false
        updateCalendarSettings(settings)
    }

    func setCalendarSelected(_ id: String, selected: Bool) {
        var settings = data.settings
        if selected { settings.selectedCalendarIDs.insert(id) } else { settings.selectedCalendarIDs.remove(id) }
        settings.didChooseInitialCalendars = true
        updateCalendarSettings(settings)
    }

    private func updateCalendarSettings(_ settings: IntervalSettings) {
        data.settings = settings
        calendarService.configure(enabled: settings.calendarIntegrationEnabled,
                                  selectedCalendarIDs: settings.selectedCalendarIDs)
        save()
    }

    func checkpointForTermination() {
        let actionDate = Date()
        now = actionDate
        reconcile(at: actionDate)
        if var value = data.activeTimer, value.kind == .focus, value.status == .running {
            TimerEngine.pause(&value, now: actionDate)
            data.activeTimer = value
            notifications.cancel(value)
            save()
        }
        audio.stop()
    }

    private func prepareForSleep() {
        now = Date()
        reconcile(at: now)
        audio.stop()
        guard var value = data.activeTimer, value.kind == .focus, value.status == .running else { return }
        TimerEngine.pause(&value, now: now); data.activeTimer = value; save()
        notifications.cancel(value)
    }

    @discardableResult private func reconcile(at date: Date) -> Bool {
        guard var value = data.activeTimer else { return false }
        let priorDeadline = value.deadline
        guard TimerEngine.reconcile(&value, now: date) else { return false }
        record(value, outcome: .completed, endedAt: priorDeadline ?? date, activeDuration: value.duration)
        let completedSession = data.sessions.last?.id
        notifications.completed(value); audio.stop()
        if value.kind == .focus {
            data.completedFocusCount += 1
            completionSessionID = completedSession
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
    private func checkpoint(force: Bool = false) {
        guard var value = data.activeTimer, value.kind == .focus, value.status == .running else { return }
        let elapsed = TimerEngine.activeDuration(value, now: now)
        guard force || elapsed - value.elapsedBeforePause >= 5 else { return }
        value.elapsedBeforePause = elapsed // Deadline remains authoritative while running.
        data.activeTimer = value; save()
    }
    private func syncServices(for value: TimerState) {
        if value.status == .running {
            notifications.schedule(timer: value)
            do { try audio.play(value.kind == .focus ? data.settings.focusSound : data.settings.breakSound, volume: data.settings.soundVolume); audioError = nil }
            catch { audioError = "Ambient sound unavailable: \(error.localizedDescription)" }
        } else { notifications.cancel(value); audio.stop() }
    }
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
