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
    var reminderOverlay: ReminderOverlay?
    let notifications: NotificationService
    let calendarService: CalendarService
    private let audio = AmbientAudio()
    private let persistence: JSONStore
    private var persistenceLocked = false
    private var ticker: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var reminderEngine = ReminderEngine()
    private let overlayController = ReminderOverlayController()
    private var systemIsSleeping = false
    private var screenSaverIsRunning = false
    private var screenIsLocked = false
    private var workspaceSessionIsActive = false
    private var sessionIsOnConsole = false
    private var previewReminderID: UUID?
    private var previewExpiresAt: Date?
    private let runtimeEnabled: Bool

    init(persistence: JSONStore = JSONStore(), calendarService: CalendarService? = nil, runtimeEnabled: Bool = true) {
        self.persistence = persistence
        self.runtimeEnabled = runtimeEnabled
        self.notifications = NotificationService(enabled: runtimeEnabled)
        self.calendarService = calendarService ?? CalendarService()
        var recoveredRunningFocus = false
        do { data = try persistence.load() } catch {
            data = PersistedData()
            persistenceError = "Couldn’t read your saved data. Interval is read-only to protect the original file: \(error.localizedDescription)"
            persistenceLocked = true
        }
        if runtimeEnabled, var restored = data.activeTimer, restored.kind == .focus, restored.status == .running {
            notifications.cancel(restored)
            restored.status = .paused
            restored.deadline = nil
            data.activeTimer = restored
            recoveryMessage = "A focus interval was running when Interval closed. It was paused without counting time away."
            recoveredRunningFocus = true
        }
        if data.activeTimer == nil { data.activeTimer = timer(for: .focus) }
        if runtimeEnabled {
            self.calendarService.configure(enabled: data.settings.calendarIntegrationEnabled,
                                           selectedCalendarIDs: data.settings.selectedCalendarIDs)
        }
        completionSessionID = data.sessions.last(where: { $0.kind == .focus && $0.outcome == .completed && $0.feedback == nil })?.id
        guard runtimeEnabled else { return }
        notifications.fallback = { [weak self] message in self?.inAppNotification = message }
        audio.failure = { [weak self] message in self?.audioError = message }
        if recoveredRunningFocus { save() }
        reconcileReminderBacklog(at: now)
        reconcile(at: now)
        if data.activeTimer?.kind != .focus, data.activeTimer?.status == .running { syncServices(for: timer) }
        workspaceSessionIsActive = true
        refreshSessionState()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self else { return }
                self.now = Date(); self.reconcile(at: self.now); self.tickReminders(at: self.now)
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
                self.systemIsSleeping = false; self.refreshSessionState(); self.tickReminders(at: self.now)
            }
        })
        observers.append(center.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.workspaceSessionIsActive = false; self?.sessionBecameUnavailable() }
        })
        observers.append(center.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.workspaceSessionIsActive = true; self?.refreshSessionState(); self?.tickReminders(at: Date()) }
        })
        for name in ["com.apple.screensaver.didstart", "com.apple.screensaver.didstop"] {
            observers.append(DistributedNotificationCenter.default().addObserver(forName: .init(name), object: nil, queue: .main) { [weak self] note in
                Task { @MainActor in
                    self?.screenSaverIsRunning = note.name.rawValue.hasSuffix("didstart")
                    self?.refreshSessionState()
                    if self?.sessionIsActive == false { self?.sessionBecameUnavailable() } else { self?.tickReminders(at: Date()) }
                }
            })
        }
        for name in ["com.apple.screenIsLocked", "com.apple.screenIsUnlocked"] {
            observers.append(DistributedNotificationCenter.default().addObserver(forName: .init(name), object: nil, queue: .main) { [weak self] note in
                Task { @MainActor in
                    self?.screenIsLocked = note.name.rawValue.hasSuffix("Locked")
                    self?.refreshSessionState()
                    if self?.sessionIsActive == false { self?.sessionBecameUnavailable() } else { self?.tickReminders(at: Date()) }
                }
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.overlayController.close(); self.tickReminders(at: Date())
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
    var nextReminder: Reminder? { data.reminders.filter { $0.isEnabled && $0.effectiveDueAt != nil }.min { $0.effectiveDueAt! < $1.effectiveDueAt! } }

    func addReminder() -> UUID {
        let value = Reminder(title: "New reminder", dueAt: now.addingTimeInterval(1_200))
        data.reminders.append(value); save(); return value.id
    }
    func addReminder(template: Reminder) -> UUID {
        var value = template.clamped(); value.id = UUID(); value.dueAt = now.addingTimeInterval(value.intervalSeconds)
        value.snoozedUntil = nil; data.reminders.append(value); save(); return value.id
    }
    func updateReminder(_ reminder: Reminder) {
        guard let index = data.reminders.firstIndex(where: { $0.id == reminder.id }) else { return }
        let old = data.reminders[index]
        var value = reminder.clamped()
        if value.intervalSeconds != old.intervalSeconds { value.dueAt = now.addingTimeInterval(value.intervalSeconds); value.snoozedUntil = nil }
        data.reminders[index] = value
        if value != old { cancelOverlay(for: value.id) }
        save()
    }
    func deleteReminder(_ id: UUID) {
        data.reminders.removeAll { $0.id == id }; cancelOverlay(for: id); save()
    }
    func snoozeReminder(_ id: UUID, seconds: TimeInterval = 300) {
        if previewReminderID == id { cancelOverlay(for: id); return }
        reminderEngine.snooze(id, reminders: &data.reminders, now: Date(), seconds: seconds); cancelOverlay(for: id); save()
    }
    func dismissReminder(_ id: UUID) {
        if previewReminderID == id { cancelOverlay(for: id); return }
        reminderEngine.dismiss(id, reminders: &data.reminders, now: Date()); cancelOverlay(for: id); save()
    }
    func previewReminder(_ id: UUID) {
        guard let reminder = data.reminders.first(where: { $0.id == id }) else { return }
        cancelCurrentOverlay()
        let shownAt = Date(); previewReminderID = id; previewExpiresAt = shownAt.addingTimeInterval(reminder.displaySeconds)
        reminderOverlay = .reminder(reminderID: id, shownAt: shownAt)
        overlayController.update(reminderOverlay, reminder: reminder, store: self)
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
        tickReminders(at: actionDate)
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
        guard runtimeEnabled else { return }
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
        systemIsSleeping = true; sessionBecameUnavailable()
        now = Date()
        reconcile(at: now)
        audio.stop()
        guard var value = data.activeTimer, value.kind == .focus, value.status == .running else { return }
        TimerEngine.pause(&value, now: now); data.activeTimer = value; save()
        notifications.cancel(value)
    }

    private var sessionIsActive: Bool {
        !systemIsSleeping && !screenSaverIsRunning && !screenIsLocked && workspaceSessionIsActive && sessionIsOnConsole
    }
    private func refreshSessionState() {
        guard let dictionary = CGSessionCopyCurrentDictionary() as? [String: Any] else { sessionIsOnConsole = false; return }
        sessionIsOnConsole = dictionary[kCGSessionOnConsoleKey as String] as? Bool ?? false
    }
    private func sessionBecameUnavailable() {
        reminderEngine.cancel(); reminderOverlay = nil; previewReminderID = nil; previewExpiresAt = nil; overlayController.close()
    }

    private func tickReminders(at date: Date) {
        guard runtimeEnabled else { return }
        if let previewReminderID, let expiry = previewExpiresAt, date < expiry {
            guard let reminder = data.reminders.first(where: { $0.id == previewReminderID }) else { cancelOverlay(for: previewReminderID); return }
            overlayController.update(reminderOverlay, reminder: reminder, store: self); return
        } else if previewReminderID != nil { cancelCurrentOverlay() }
        let before = data.reminders
        let focusBusy = data.activeTimer.map { $0.kind == .focus && ($0.status == .running || $0.status == .paused) } ?? false
        let idleSeconds = UserIdleMonitor.idleSeconds
        let environment = ReminderEnvironment(isSessionActive: sessionIsActive, isUserIdle: idleSeconds >= 1,
            focusIsRunningOrPaused: focusBusy, calendarHasEvent: calendarService.hasEvent(at: date), idleSeconds: idleSeconds)
        reminderOverlay = reminderEngine.tick(reminders: &data.reminders, now: date, environment: environment)
        if before != data.reminders { save() }
        let reminder = reminderOverlay.flatMap { visible in data.reminders.first { $0.id == visible.reminderID } }
        overlayController.update(reminderOverlay, reminder: reminder, store: self)
    }

    private func reconcileReminderBacklog(at date: Date) {
        let before = data.reminders
        _ = reminderEngine.tick(reminders: &data.reminders, now: date,
            environment: .init(isSessionActive: sessionIsActive, isUserIdle: false))
        reminderEngine.cancel()
        if before != data.reminders { save() }
    }
    private func cancelOverlay(for id: UUID) {
        guard reminderOverlay?.reminderID == id || previewReminderID == id else { return }
        reminderEngine.cancel(reminderID: id); reminderOverlay = nil; previewReminderID = nil; previewExpiresAt = nil; overlayController.close()
    }
    private func cancelCurrentOverlay() {
        reminderEngine.cancel(); reminderOverlay = nil; previewReminderID = nil; previewExpiresAt = nil; overlayController.close()
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
