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
  let updates: UpdateService
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
  var selection: Destination? = .focus
  var storageURL: URL { persistence.fileURL }

  init(
    persistence: JSONStore = JSONStore(), calendarService: CalendarService? = nil,
    runtimeEnabled: Bool = true
  ) {
    self.persistence = persistence
    self.runtimeEnabled = runtimeEnabled
    self.notifications = NotificationService(enabled: runtimeEnabled)
    self.calendarService = calendarService ?? CalendarService()
    self.updates = UpdateService(enabled: runtimeEnabled)
    do { data = try persistence.load() } catch {
      data = PersistedData()
      persistenceError =
        "Couldn’t read your saved data. Interval is read-only to protect the original file: \(error.localizedDescription)"
      persistenceLocked = true
    }
    if var restored = data.activeTimer, restored.status == .paused {
      let endedAt = restored.startedAt?.addingTimeInterval(restored.elapsedBeforePause) ?? now
      TimerEngine.abandon(&restored)
      record(
        restored, outcome: .abandoned, endedAt: endedAt,
        activeDuration: restored.elapsedBeforePause)
      data.activeTimer = timer(for: .focus)
      recoveryMessage = "A legacy paused cycle was moved to history."
      save()
    }
    if data.activeTimer == nil { data.activeTimer = timer(for: .focus) }
    if runtimeEnabled {
      self.calendarService.configure(
        enabled: data.settings.calendarIntegrationEnabled,
        selectedCalendarIDs: data.settings.selectedCalendarIDs)
    }
    if timer.kind != .focus, timer.status == .ready,
      let completed = data.sessions.last, completed.kind == .focus, completed.outcome == .completed
    {
      completionSessionID = completed.id
    }
    reconcile(at: now, autoStart: false)
    guard runtimeEnabled else { return }
    updates.shouldDeferInstall = { [weak self] in
      guard let self else { return false }
      return self.timer.status == .running || self.reminderOverlay != nil
        || self.completionSessionID != nil
    }
    updates.prepareForInstall = { [weak self] in self?.checkpointForTermination() }
    updates.start()
    notifications.fallback = { [weak self] message in self?.inAppNotification = message }
    audio.failure = { [weak self] message in self?.audioError = message }
    reconcileReminderBacklog(at: now)
    if data.activeTimer?.status == .running { syncServices(for: timer) }
    workspaceSessionIsActive = true
    refreshSessionState()
    ticker = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(250))
        guard let self else { return }
        self.now = Date()
        self.reconcile(at: self.now)
        self.tickReminders(at: self.now)
        if Int(self.now.timeIntervalSince1970) % 5 == 0 { self.checkpoint() }
      }
    }
    let center = NSWorkspace.shared.notificationCenter
    observers.append(
      center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) {
        [weak self] _ in
        Task { @MainActor in self?.prepareForSleep() }
      })
    observers.append(
      center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) {
        [weak self] _ in
        Task { @MainActor in
          guard let self else { return }
          self.systemIsSleeping = false
          self.refreshSessionState()
          self.sessionBecameAvailable()
        }
      })
    observers.append(
      center.addObserver(
        forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main
      ) { [weak self] _ in
        Task { @MainActor in
          self?.workspaceSessionIsActive = false
          self?.sessionBecameUnavailable()
        }
      })
    observers.append(
      center.addObserver(
        forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main
      ) { [weak self] _ in
        Task { @MainActor in
          self?.workspaceSessionIsActive = true
          self?.refreshSessionState()
          self?.sessionBecameAvailable()
        }
      })
    for name in ["com.apple.screensaver.didstart", "com.apple.screensaver.didstop"] {
      observers.append(
        DistributedNotificationCenter.default().addObserver(
          forName: .init(name), object: nil, queue: .main
        ) { [weak self] note in
          Task { @MainActor in
            self?.screenSaverIsRunning = note.name.rawValue.hasSuffix("didstart")
            self?.refreshSessionState()
            if self?.sessionIsActive == false {
              self?.sessionBecameUnavailable()
            } else {
              self?.sessionBecameAvailable()
            }
          }
        })
    }
    for name in ["com.apple.screenIsLocked", "com.apple.screenIsUnlocked"] {
      observers.append(
        DistributedNotificationCenter.default().addObserver(
          forName: .init(name), object: nil, queue: .main
        ) { [weak self] note in
          Task { @MainActor in
            self?.screenIsLocked = note.name.rawValue.hasSuffix("Locked")
            self?.refreshSessionState()
            if self?.sessionIsActive == false {
              self?.sessionBecameUnavailable()
            } else {
              self?.sessionBecameAvailable()
            }
          }
        })
    }
    observers.append(
      NotificationCenter.default.addObserver(
        forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
      ) { [weak self] _ in
        Task { @MainActor in
          guard let self else { return }
          self.overlayController.close()
          self.tickReminders(at: Date())
        }
      })
    observers.append(
      center.addObserver(
        forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
      ) { [weak self] notification in
        guard
          let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
            as? NSRunningApplication,
          application.bundleIdentifier == Bundle.main.bundleIdentifier
        else { return }
        Task { @MainActor in self?.calendarService.applicationDidActivate() }
      })
  }

  var timer: TimerState { data.activeTimer ?? timer(for: .focus) }
  var remaining: TimeInterval { TimerEngine.remaining(timer, now: now) }
  var suggestedBreak: TimerKind {
    let cadence = max(1, data.settings.longBreakEvery)
    return data.completedFocusCount > 0 && data.completedFocusCount % cadence == 0
      ? .longBreak : .shortBreak
  }
  var nextReminder: Reminder? {
    data.reminders.filter { $0.isEnabled && $0.effectiveDueAt != nil }.min {
      $0.effectiveDueAt! < $1.effectiveDueAt!
    }
  }

  func addReminder() -> UUID {
    let value = Reminder(title: "New reminder", dueAt: now.addingTimeInterval(1_200))
    data.reminders.append(value)
    save()
    return value.id
  }
  func addReminder(template: Reminder) -> UUID {
    var value = template.clamped()
    value.id = UUID()
    value.dueAt = now.addingTimeInterval(value.intervalSeconds)
    value.snoozedUntil = nil
    data.reminders.append(value)
    save()
    return value.id
  }
  func updateReminder(_ reminder: Reminder) {
    guard let index = data.reminders.firstIndex(where: { $0.id == reminder.id }) else { return }
    let old = data.reminders[index]
    var value = reminder.clamped()
    if value.intervalSeconds != old.intervalSeconds {
      value.dueAt = now.addingTimeInterval(value.intervalSeconds)
      value.snoozedUntil = nil
    }
    data.reminders[index] = value
    if value != old { cancelOverlay(for: value.id) }
    save()
  }
  func deleteReminder(_ id: UUID) {
    data.reminders.removeAll { $0.id == id }
    cancelOverlay(for: id)
    save()
  }
  func snoozeReminder(_ id: UUID, seconds: TimeInterval = 300) {
    if previewReminderID == id {
      cancelOverlay(for: id)
      return
    }
    reminderEngine.snooze(id, reminders: &data.reminders, now: Date(), seconds: seconds)
    cancelOverlay(for: id)
    save()
  }
  func dismissReminder(_ id: UUID) {
    if previewReminderID == id {
      cancelOverlay(for: id)
      return
    }
    reminderEngine.dismiss(id, reminders: &data.reminders, now: Date())
    cancelOverlay(for: id)
    save()
  }
  func previewReminder(_ id: UUID) {
    guard let reminder = data.reminders.first(where: { $0.id == id }) else { return }
    cancelCurrentOverlay()
    let shownAt = Date()
    previewReminderID = id
    previewExpiresAt = shownAt.addingTimeInterval(reminder.displaySeconds)
    reminderOverlay = .reminder(reminderID: id, shownAt: shownAt)
    if runtimeEnabled { overlayController.update(reminderOverlay, reminder: reminder, store: self) }
  }

  func startSession() {
    if completionSessionID != nil {
      showFocus()
      return
    }
    let actionDate = Date()
    now = actionDate
    if reconcile(at: actionDate, autoStart: false) { return }
    guard var value = data.activeTimer, value.status == .ready else { return }
    inAppNotification = nil
    recoveryMessage = nil
    TimerEngine.start(&value, now: actionDate)
    data.activeTimer = value
    save()
    syncServices(for: value)
    tickReminders(at: actionDate)
  }

  func abandon() {
    let actionDate = Date()
    now = actionDate
    if reconcile(at: actionDate, autoStart: false) {
      completionSessionID = nil
      data.activeTimer = timer(for: .focus)
      save()
      return
    }
    guard var value = data.activeTimer, value.status == .running else {
      return
    }
    let activeDuration = TimerEngine.activeDuration(value, now: actionDate)
    TimerEngine.abandon(&value)
    notifications.cancel(value)
    audio.stop()
    record(value, outcome: .abandoned, endedAt: actionDate, activeDuration: activeDuration)
    data.activeTimer = timer(for: .focus)
    save()
  }

  func adjustCurrentTime(by seconds: TimeInterval, at date: Date = Date()) {
    now = date
    if reconcile(at: date, autoStart: false) { return }
    guard completionSessionID == nil, var value = data.activeTimer,
      value.status == .ready || value.status == .running
    else { return }
    TimerEngine.adjustRemaining(&value, by: seconds, now: date)
    data.activeTimer = value
    save()
    syncServices(for: value)
  }

  func startBreakNow(at date: Date = Date()) {
    now = date
    if reconcile(at: date, autoStart: false) { return }
    guard completionSessionID == nil, var focus = data.activeTimer, focus.kind == .focus else {
      return
    }
    if focus.status == .running {
      let activeDuration = TimerEngine.activeDuration(focus, now: date)
      TimerEngine.abandon(&focus)
      notifications.cancel(focus)
      audio.stop()
      record(focus, outcome: .abandoned, endedAt: date, activeDuration: activeDuration)
    } else {
      guard focus.status == .ready else { return }
    }
    // Manual breaks do not consume or repeat the completed-focus cadence.
    var next = timer(for: .shortBreak)
    TimerEngine.start(&next, now: date)
    data.activeTimer = next
    inAppNotification = nil
    recoveryMessage = nil
    save()
    syncServices(for: next)
    tickReminders(at: date)
  }

  func endBreak(at date: Date = Date()) {
    now = date
    guard let current = data.activeTimer, current.kind != .focus, current.status == .running else {
      return
    }
    if reconcile(at: date, autoStart: false) { return }
    guard let value = data.activeTimer, value.id == current.id, value.status == .running else {
      return
    }
    let elapsed = TimerEngine.activeDuration(value, now: date)
    notifications.cancel(value)
    audio.stop()
    record(value, outcome: .completed, endedAt: date, activeDuration: elapsed)
    data.activeTimer = timer(for: .focus)
    inAppNotification = nil
    recoveryMessage = nil
    save()
  }

  func addTodo(_ text: String) {
    let title = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty else { return }
    data.todos.append(TodoItem(title: title))
    save()
  }
  func updateTodoTitle(_ id: UUID, title: String) {
    guard let index = data.todos.firstIndex(where: { $0.id == id }) else { return }
    let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty else { return }
    data.todos[index].title = title
    save()
  }
  func toggleTodo(_ id: UUID) {
    guard let index = data.todos.firstIndex(where: { $0.id == id }) else { return }
    data.todos[index].isCompleted.toggle()
    save()
  }
  func deleteTodo(_ id: UUID) {
    guard data.todos.contains(where: { $0.id == id }) else { return }
    data.todos.removeAll { $0.id == id }
    save()
  }
  func setSessionTitle(_ title: String) {
    guard title != data.sessionTitle else { return }
    let date = Date()
    now = date
    reconcile(at: date, autoStart: false)
    data.sessionTitle = title
    data.activeTimer?.title = title
    save()
  }
  func selectCategory(_ id: UUID?) {
    let date = Date()
    now = date
    reconcile(at: date, autoStart: false)
    guard id == nil || data.categories.contains(where: { $0.id == id }) else { return }
    let categoryName = data.categories.first(where: { $0.id == id })?.name
    data.selectedCategoryID = id
    data.activeTimer?.categoryID = id
    data.activeTimer?.categoryName = categoryName
    save()
  }
  @discardableResult func addCategory(_ name: String) -> UUID? {
    let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else { return nil }
    let date = Date()
    now = date
    reconcile(at: date, autoStart: false)
    if let existing = data.categories.first(where: {
      $0.name.compare(name, options: [.caseInsensitive]) == .orderedSame
    }) {
      data.selectedCategoryID = existing.id
      data.activeTimer?.categoryID = existing.id
      data.activeTimer?.categoryName = existing.name
      save()
      return existing.id
    }
    let category = SessionCategory(name: name)
    data.categories.append(category)
    data.selectedCategoryID = category.id
    data.activeTimer?.categoryID = category.id
    data.activeTimer?.categoryName = category.name
    save()
    return category.id
  }
  func renameCategory(_ id: UUID, name: String) {
    let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty,
      !data.categories.contains(where: {
        $0.id != id && $0.name.compare(name, options: [.caseInsensitive]) == .orderedSame
      }), let index = data.categories.firstIndex(where: { $0.id == id })
    else { return }
    let date = Date()
    now = date
    reconcile(at: date, autoStart: false)
    data.categories[index].name = name
    if data.activeTimer?.categoryID == id { data.activeTimer?.categoryName = name }
    save()
  }
  func deleteCategory(_ id: UUID) {
    guard data.categories.contains(where: { $0.id == id }) else { return }
    let date = Date()
    now = date
    reconcile(at: date, autoStart: false)
    data.categories.removeAll { $0.id == id }
    if data.selectedCategoryID == id { data.selectedCategoryID = nil }
    if data.activeTimer?.status == .ready && data.activeTimer?.categoryID == id {
      data.activeTimer?.categoryID = nil
      data.activeTimer?.categoryName = nil
    }
    save()
  }
  func updateSession(id: UUID, feedback: SessionFeedback?, journal: String) {
    guard let index = data.sessions.firstIndex(where: { $0.id == id }) else { return }
    data.sessions[index].feedback = feedback?.rawValue
    data.sessions[index].journal = journal.isEmpty ? nil : journal
    save()
  }
  func continueAfterReflection(at date: Date = Date()) {
    guard completionSessionID != nil else { return }
    completionSessionID = nil
    guard var next = data.activeTimer, next.kind != .focus, next.status == .ready else { return }
    now = date
    TimerEngine.start(&next, now: date)
    data.activeTimer = next
    inAppNotification = nil
    save()
    syncServices(for: next)
    tickReminders(at: date)
  }
  func showFocus() { selection = .focus }
  func exportData(to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(data).write(to: url, options: .atomic)
  }
  func updateSettings(_ settings: IntervalSettings) {
    let old = data.settings
    data.settings = settings.clamped()
    if data.activeTimer?.status == .ready {
      data.activeTimer = timer(for: data.activeTimer?.kind ?? .focus)
    }
    save()
    if data.activeTimer?.status == .running,
      old.focusSound != settings.focusSound || old.breakSound != settings.breakSound
        || old.soundVolume != settings.soundVolume
    {
      syncAudio(for: timer)
    }
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
    var settings = data.settings
    settings.calendarIntegrationEnabled = false
    updateCalendarSettings(settings)
  }

  func setCalendarSelected(_ id: String, selected: Bool) {
    var settings = data.settings
    if selected {
      settings.selectedCalendarIDs.insert(id)
    } else {
      settings.selectedCalendarIDs.remove(id)
    }
    settings.didChooseInitialCalendars = true
    updateCalendarSettings(settings)
  }

  private func updateCalendarSettings(_ settings: IntervalSettings) {
    data.settings = settings
    calendarService.configure(
      enabled: settings.calendarIntegrationEnabled,
      selectedCalendarIDs: settings.selectedCalendarIDs)
    save()
  }

  func checkpointForTermination() {
    guard runtimeEnabled else { return }
    checkpointForInactivity(at: Date())
  }

  func checkpointForInactivity(at date: Date) {
    now = date
    reconcile(at: date, autoStart: false)
    checkpoint(force: true)
    audio.stop()
  }

  private func prepareForSleep() {
    systemIsSleeping = true
    sessionBecameUnavailable()
  }

  private var sessionIsActive: Bool {
    !systemIsSleeping && !screenSaverIsRunning && !screenIsLocked && workspaceSessionIsActive
      && sessionIsOnConsole
  }
  private func refreshSessionState() {
    guard let dictionary = CGSessionCopyCurrentDictionary() as? [String: Any] else {
      sessionIsOnConsole = false
      return
    }
    sessionIsOnConsole = dictionary[kCGSessionOnConsoleKey as String] as? Bool ?? false
  }
  private func sessionBecameUnavailable() {
    checkpointForInactivity(at: Date())
    reminderEngine.cancel()
    reminderOverlay = nil
    previewReminderID = nil
    previewExpiresAt = nil
    overlayController.close()
  }
  private func sessionBecameAvailable() {
    guard sessionIsActive else { return }
    let date = Date()
    now = date
    if !reconcile(at: date, autoStart: false), data.activeTimer?.status == .running {
      syncServices(for: timer)
    }
    tickReminders(at: date)
  }

  private func tickReminders(at date: Date) {
    guard runtimeEnabled else { return }
    if let previewReminderID, let expiry = previewExpiresAt, date < expiry {
      guard let reminder = data.reminders.first(where: { $0.id == previewReminderID }) else {
        cancelOverlay(for: previewReminderID)
        return
      }
      overlayController.update(reminderOverlay, reminder: reminder, store: self)
      return
    } else if previewReminderID != nil {
      cancelCurrentOverlay()
    }
    let before = data.reminders
    let focusBusy =
      data.activeTimer.map { $0.kind == .focus && $0.status == .running }
      ?? false
    let idleSeconds = UserIdleMonitor.idleSeconds
    let environment = ReminderEnvironment(
      isSessionActive: sessionIsActive, isUserIdle: idleSeconds >= 1,
      focusIsRunningOrPaused: focusBusy, calendarHasEvent: calendarService.hasEvent(at: date),
      idleSeconds: idleSeconds)
    reminderOverlay = reminderEngine.tick(
      reminders: &data.reminders, now: date, environment: environment)
    if before != data.reminders { save() }
    let reminder = reminderOverlay.flatMap { visible in
      data.reminders.first { $0.id == visible.reminderID }
    }
    overlayController.update(reminderOverlay, reminder: reminder, store: self)
  }

  private func reconcileReminderBacklog(at date: Date) {
    let before = data.reminders
    _ = reminderEngine.tick(
      reminders: &data.reminders, now: date,
      environment: .init(isSessionActive: sessionIsActive, isUserIdle: false))
    reminderEngine.cancel()
    if before != data.reminders { save() }
  }
  private func cancelOverlay(for id: UUID) {
    guard reminderOverlay?.reminderID == id || previewReminderID == id else { return }
    reminderEngine.cancel(reminderID: id)
    reminderOverlay = nil
    previewReminderID = nil
    previewExpiresAt = nil
    overlayController.close()
  }
  private func cancelCurrentOverlay() {
    reminderEngine.cancel()
    reminderOverlay = nil
    previewReminderID = nil
    previewExpiresAt = nil
    overlayController.close()
  }

  @discardableResult func reconcile(at date: Date, autoStart: Bool = true) -> Bool {
    now = date
    guard var value = data.activeTimer else { return false }
    let priorDeadline = value.deadline
    guard TimerEngine.reconcile(&value, now: date) else { return false }
    record(
      value, outcome: .completed, endedAt: priorDeadline ?? date, activeDuration: value.duration)
    let completedSession = data.sessions.last?.id
    notifications.completed(value)
    audio.stop()
    if value.kind == .focus {
      data.completedFocusCount += 1
      completionSessionID = completedSession
      showFocus()
      data.activeTimer = timer(for: suggestedBreak)
      save()
      syncServices(for: timer)
      return true
    } else {
      data.activeTimer = timer(for: .focus)
    }
    // Start at the observed transition, never replay phases during time away.
    if autoStart && (!runtimeEnabled || sessionIsActive) {
      var next = timer
      TimerEngine.start(&next, now: date)
      data.activeTimer = next
    }
    save()
    syncServices(for: timer)
    return true
  }

  private func record(
    _ timer: TimerState, outcome: TimerStatus, endedAt: Date, activeDuration: TimeInterval
  ) {
    guard !data.sessions.contains(where: { $0.timerID == timer.id && $0.outcome == outcome }) else {
      return
    }
    data.sessions.append(
      SessionRecord(
        timerID: timer.id, kind: timer.kind, startedAt: timer.startedAt ?? endedAt,
        endedAt: endedAt, plannedDuration: timer.duration,
        activeDuration: activeDuration, outcome: outcome, title: timer.title,
        categoryID: timer.categoryID, categoryName: timer.categoryName))
  }

  private func timer(for kind: TimerKind) -> TimerState {
    let category = data.categories.first { $0.id == data.selectedCategoryID }
    return TimerState(
      kind: kind, duration: data.settings.duration(for: kind), title: data.sessionTitle,
      categoryID: category?.id, categoryName: category?.name)
  }
  private func checkpoint(force: Bool = false) {
    guard var value = data.activeTimer, value.status == .running else {
      return
    }
    let elapsed = TimerEngine.activeDuration(value, now: now)
    guard force || elapsed - value.elapsedBeforePause >= 5 else { return }
    value.elapsedBeforePause = elapsed  // Deadline remains authoritative while running.
    data.activeTimer = value
    save()
  }
  private func syncServices(for value: TimerState) {
    if value.status == .running {
      notifications.schedule(timer: value)
      syncAudio(for: value)
    } else {
      notifications.cancel(value)
      audio.stop()
    }
  }
  private func syncAudio(for value: TimerState) {
    guard runtimeEnabled else { return }
    do {
      try audio.play(
        value.kind == .focus ? data.settings.focusSound : data.settings.breakSound,
        volume: data.settings.soundVolume)
      audioError = nil
    } catch { audioError = "Ambient sound unavailable: \(error.localizedDescription)" }
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
