import AppKit
import IntervalCore
import SwiftUI

struct SnapshotRequest {
  let path: String
  let scene: String
  let composited: Bool
  let appearance: AppAppearance

  init?(arguments: [String]) {
    guard let index = arguments.firstIndex(of: "--snapshot"), arguments.indices.contains(index + 1)
    else { return nil }
    path = arguments[index + 1]
    composited = arguments.contains("--snapshot-composited")
    if let appearanceIndex = arguments.firstIndex(of: "--snapshot-appearance"),
      arguments.indices.contains(appearanceIndex + 1)
    {
      appearance = AppAppearance(rawValue: arguments[appearanceIndex + 1]) ?? .system
    } else {
      appearance = .dark
    }
    if let sceneIndex = arguments.firstIndex(of: "--snapshot-scene"),
      arguments.indices.contains(sceneIndex + 1)
    {
      scene = arguments[sceneIndex + 1]
    } else {
      scene = "focus"
    }
  }
}

@MainActor enum SnapshotRenderer {
  static let fixtureNow = Date(timeIntervalSince1970: 1_800_000_000.125)
  static let calendarFixture = [
    CalendarEventSnapshot(
      id: "calendar-1", title: "Design review",
      start: fixtureNow.addingTimeInterval(-900), end: fixtureNow.addingTimeInterval(900),
      allDay: false, calendarName: "Work"),
    CalendarEventSnapshot(
      id: "calendar-2", title: "Team offsite",
      start: Calendar.current.startOfDay(for: fixtureNow),
      end: Calendar.current.date(
        byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: fixtureNow))!,
      allDay: true, calendarName: "Work"),
    CalendarEventSnapshot(
      id: "calendar-3", title: "Dinner",
      start: fixtureNow.addingTimeInterval(10_800), end: fixtureNow.addingTimeInterval(14_400),
      allDay: false, calendarName: "Personal"),
  ]

  static func fixture(scene: String) -> PersistedData {
    let deepWork = SessionCategory(
      id: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!, name: "Deep Work")
    let clientWork = SessionCategory(
      id: UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!, name: "Client Work")
    let timerID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    var timer = TimerState(
      id: timerID, kind: .focus, duration: 1_500, status: .ready,
      title: "Polish launch narrative", categoryID: deepWork.id, categoryName: deepWork.name)
    if scene.hasPrefix("reflection") {
      timer = TimerState(
        id: timerID, kind: .shortBreak, duration: 300, status: .ready,
        title: "Polish launch narrative", categoryID: deepWork.id, categoryName: deepWork.name)
    }
    if scene == "dashboard-running" || scene == "menu" || scene == "time-options"
      || scene == "time-options-minus" || scene == "history-running" || scene == "history-previous"
    {
      timer.status = .running
      timer.startedAt = fixtureNow.addingTimeInterval(-420)
      timer.deadline = fixtureNow.addingTimeInterval(1_080)
    }
    if scene == "dashboard-break" || scene == "history-break" || scene == "menu-break" {
      timer = TimerState(
        id: timerID, kind: .shortBreak, duration: 300, status: .running,
        startedAt: fixtureNow.addingTimeInterval(-60),
        deadline: fixtureNow.addingTimeInterval(240), title: "Polish launch narrative",
        categoryID: deepWork.id, categoryName: deepWork.name)
    }
    if scene == "dashboard-overtime" || scene == "menu-overtime" {
      timer = TimerState(
        id: timerID, kind: .shortBreak, duration: 300, status: .completed,
        startedAt: fixtureNow.addingTimeInterval(-385),
        deadline: fixtureNow.addingTimeInterval(-85),
        title: "Polish launch narrative", categoryID: deepWork.id, categoryName: deepWork.name)
    }
    var session = SessionRecord(
      id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
      timerID: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!, kind: .focus,
      startedAt: fixtureNow.addingTimeInterval(-3_600),
      endedAt: fixtureNow.addingTimeInterval(-2_100),
      plannedDuration: 1_500, activeDuration: 1_500, outcome: .completed,
      feedback: scene == "reflection" ? nil : "focused",
      journal: "Clear progress on the launch plan.", title: "Draft launch brief",
      categoryID: deepWork.id, categoryName: deepWork.name)
    let additionalSessions = [
      SessionRecord(
        id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
        timerID: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!, kind: .focus,
        startedAt: fixtureNow.addingTimeInterval(-8_100),
        endedAt: fixtureNow.addingTimeInterval(-6_600), plannedDuration: 1_500,
        activeDuration: 1_500, outcome: .completed, feedback: "focused",
        journal: "Resolved the remaining navigation edge cases.", title: "Prototype navigation",
        categoryID: deepWork.id, categoryName: deepWork.name),
      SessionRecord(
        id: UUID(uuidString: "66666666-6666-6666-6666-666666666666")!,
        timerID: UUID(uuidString: "77777777-7777-7777-7777-777777777777")!, kind: .focus,
        startedAt: fixtureNow.addingTimeInterval(-14_400),
        endedAt: fixtureNow.addingTimeInterval(-12_900), plannedDuration: 1_500,
        activeDuration: 1_500, outcome: .completed, feedback: "neutral",
        journal: "Captured decisions and sent the follow-up.", title: "Acme design review",
        categoryID: clientWork.id, categoryName: clientWork.name),
      SessionRecord(
        id: UUID(uuidString: "88888888-8888-8888-8888-888888888888")!,
        timerID: UUID(uuidString: "99999999-9999-9999-9999-999999999999")!, kind: .focus,
        startedAt: fixtureNow.addingTimeInterval(-90_000),
        endedAt: fixtureNow.addingTimeInterval(-88_800), plannedDuration: 1_500,
        activeDuration: 1_200, outcome: .abandoned, feedback: "distracted",
        journal: "Paused when new feedback arrived.", title: "Prepare client workshop",
        categoryID: clientWork.id, categoryName: clientWork.name),
    ]
    if scene == "history-legacy" {
      session.outcome = .abandoned
      session.isDurationEstimated = true
    }
    var settings = IntervalSettings()
    if scene == "focus-custom-colors" {
      settings.focusColor = .purple
      settings.breakColor = .orange
    }
    if scene == "history" || scene == "calendar-settings" || scene == "history-no-selection"
      || scene == "dashboard-calendar"
    {
      settings.calendarIntegrationEnabled = true
      settings.selectedCalendarIDs = ["Work", "Personal"]
      settings.didChooseInitialCalendars = true
    }
    if scene == "history-no-selection" { settings.selectedCalendarIDs = [] }
    let sessions =
      scene == "history-disabled" || scene == "history-no-selection"
      ? [] : [session] + additionalSessions
    var reminders = [
      Reminder(
        title: "Look away", message: "Look at something far away for 20 seconds.", emoji: "👀",
        intervalSeconds: 600, displaySeconds: 20, dueAt: fixtureNow.addingTimeInterval(600)),
      Reminder(
        title: "Water", message: "Take a moment to drink some water.", emoji: "💧",
        intervalSeconds: 3_600, displaySeconds: 60, presentation: .fullscreen,
        dueAt: fixtureNow.addingTimeInterval(3_600)),
    ]
    if scene == "reminders-empty" { reminders = [] }
    if scene == "reminder-max-emoji" { reminders[0].emojiSize = 180 }
    if scene == "reminder-fullscreen-long" {
      reminders[1].emojiSize = 180
      reminders[1].message = String(
        repeating: "Look into the distance and relax your shoulders. ", count: 40)
    }
    if scene == "focus-hour" { timer.duration = 3_600 }
    return PersistedData(
      settings: settings, activeTimer: timer,
      todos: [
        TodoItem(title: "Outline the launch notes"),
        TodoItem(title: "Review accessibility labels", isCompleted: true),
      ],
      sessions: sessions,
      reminders: reminders,
      completedFocusCount: 3,
      categories: [deepWork, clientWork],
      sessionTitle: "Polish launch narrative",
      selectedCategoryID: deepWork.id)
  }

  static func render(request: SnapshotRequest, store: AppStore) async throws {
    store.data.settings.appearance = request.appearance
    request.appearance.apply()
    if request.scene == "reminder-overlay" {
      // Exercise the real controller, not a reminder view inside a snapshot window.
      let controller = ReminderOverlayController()
      defer { controller.close() }
      let reminder = store.data.reminders[1]
      let existing = Set(NSApp.windows.map(\.windowNumber))
      controller.update(
        .reminder(reminderID: reminder.id, shownAt: Date().addingTimeInterval(-6)),
        reminder: reminder, store: store)
      // Production excludes reminder panels from legacy screen captures. This fixture
      // contains no user content and explicitly opts in so the compositor is tested.
      for panel in NSApp.windows where !existing.contains(panel.windowNumber) {
        panel.sharingType = .readOnly
      }
      try await Task.sleep(for: .seconds(1))
      try FileManager.default.createDirectory(
        at: URL(fileURLWithPath: request.path).deletingLastPathComponent(),
        withIntermediateDirectories: true)
      let capture = Process()
      capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
      capture.arguments = ["-x", "-D", "1", request.path]
      try capture.run()
      capture.waitUntilExit()
      guard capture.terminationStatus == 0 else { throw CocoaError(.fileWriteUnknown) }
      return
    }
    let size: NSSize
    let view: AnyView
    if request.scene == "focus-countdown" { store.now = fixtureNow.addingTimeInterval(67) }
    if request.scene == "focus-countdown-next" { store.now = fixtureNow.addingTimeInterval(68) }
    if request.scene == "dashboard-calendar" {
      store.calendarService.configure(
        enabled: true, selectedCalendarIDs: store.data.settings.selectedCalendarIDs)
      _ = store.calendarService.hasEvent(at: fixtureNow)
    }
    switch request.scene {
    case "almost-time":
      store.data.activeTimer = TimerState(
        kind: .focus, duration: 1500, status: .running,
        startedAt: fixtureNow.addingTimeInterval(-1444), deadline: fixtureNow.addingTimeInterval(56)
      )
      size = SessionCompletionController.almostTimeSize
      view = AnyView(AlmostTimeToast(store: store, startBreak: {}, extend: { _ in }))
    case "completion-toast":
      size = SessionCompletionController.toastSize
      view = AnyView(SessionCompletionToast(later: {}, reflect: {}))
    case "notch-compact", "notch-expanded", "notch-fallback", "notch-todos", "notch-reminders",
      "notch-reflection":
      let geometry =
        request.scene == "notch-fallback"
        ? NotchGeometry.fallback
        : NotchGeometry(hasHardwareNotch: true, cutoutWidth: 180, topInset: 32)
      let expanded = request.scene != "notch-compact" && request.scene != "notch-fallback"
      if request.scene == "notch-reflection" {
        store.completionSessionID = store.data.sessions.first?.id
      }
      size =
        geometry.frame(
          expanded: expanded, in: NSRect(x: 0, y: 0, width: 1440, height: 900),
          reflection: store.completionSessionID != nil
        ).size
      view = AnyView(
        NotchRootView(
          store: store, expanded: expanded, geometry: geometry, collapse: {},
          page: request.scene == "notch-todos" ? 1 : request.scene == "notch-reminders" ? 2 : 0))
    case "history", "history-disabled", "history-no-selection", "history-running", "history-break",
      "history-compact", "history-review":
      store.selection = .history
      if request.scene == "history-review" {
        store.completionSessionID = store.data.sessions.first?.id
      }
      size =
        request.scene == "history-compact"
        ? NSSize(width: 780, height: 620) : NSSize(width: 880, height: 680)
      view = AnyView(MainView(store: store))
    case "history-previous":
      size = NSSize(width: 820, height: 680)
      view = AnyView(
        HistoryView(
          store: store,
          selectedDate: Calendar.current.date(byAdding: .day, value: -1, to: store.now)
        )
        .safeAreaInset(edge: .bottom, spacing: 0) { LiveTimerBar(store: store) })
    case "history-category":
      size = NSSize(width: 820, height: 680)
      view = AnyView(HistoryView(store: store, categoryID: store.data.categories.first?.id))
    case "history-legacy":
      size = NSSize(width: 580, height: 650)
      view = AnyView(
        VStack {
          SessionRow(session: store.data.sessions[0]).padding()
          SessionInspector(store: store, session: store.data.sessions[0])
        })
    case "reminders", "reminders-empty", "reminders-compact":
      store.selection = .reminders
      size =
        request.scene == "reminders-compact"
        ? NSSize(width: 780, height: 620) : NSSize(width: 880, height: 680)
      view = AnyView(MainView(store: store))
    case "reminders-expanded":
      size = NSSize(width: 780, height: 620)
      view = AnyView(
        RemindersView(store: store, selection: store.data.reminders[0].id, advanced: true)
          .safeAreaInset(edge: .bottom, spacing: 0) { LiveTimerBar(store: store) })
    case "reminder-editor", "reminder-editor-expanded", "reminder-editor-bottom":
      size = NSSize(width: 420, height: 474)
      view = AnyView(
        RemindersView(
          store: store, selection: store.data.reminders[0].id,
          advanced: request.scene != "reminder-editor"))
    case "reminder-countdown", "reminder-countdown-paused", "reminder-countdown-light":
      let reminder = store.data.reminders[0]
      size = NSSize(width: 250, height: 64)
      view = AnyView(
        ReminderWarningView(
          reminder: reminder,
          overlay: .warning(
            reminderID: reminder.id, remaining: 7,
            isPaused: request.scene == "reminder-countdown-paused")))
    case "reminder-floating", "reminder-max-emoji":
      size = ReminderOverlayController.floatingSize(for: store.data.reminders[0])
      view = AnyView(
        ReminderTakeoverView(
          reminder: store.data.reminders[0], shownAt: Date(), skip: {}, extend: { _ in }))
    case "reminder-fullscreen", "reminder-fullscreen-long", "reminder-fullscreen-wait",
      "reminder-fullscreen-fallback":
      size = NSSize(width: 900, height: 650)
      let wallpaper =
        request.scene == "reminder-fullscreen-fallback"
        ? nil
        : NSScreen.screens.first
          .flatMap { ReminderOverlayController.wallpaperImage(for: $0) }
      view = AnyView(
        ReminderTakeoverView(
          reminder: store.data.reminders[1],
          shownAt: Date().addingTimeInterval(request.scene == "reminder-fullscreen-wait" ? 0 : -6),
          skip: {},
          extend: { _ in }, wallpaper: wallpaper))
    case "settings":
      size = NSSize(width: 560, height: 450)
      view = AnyView(SettingsView(store: store))
    case "sound-settings":
      size = NSSize(width: 560, height: 450)
      view = AnyView(SettingsView(store: store, showSound: true))
    case "calendar-settings":
      size = NSSize(width: 560, height: 450)
      view = AnyView(SettingsView(store: store, showCalendar: true))
    case "categories":
      size = NSSize(width: 400, height: 350)
      view = AnyView(CategoryManager(store: store))
    case "general-settings":
      size = NSSize(width: 560, height: 450)
      view = AnyView(SettingsView(store: store, selectedTab: 3))
    case "updates-settings":
      size = NSSize(width: 560, height: 450)
      view = AnyView(SettingsView(store: store, selectedTab: 4))
    case "reflection", "reflection-selected":
      store.completionSessionID = store.data.sessions.first?.id
      size = NSSize(width: 880, height: 680)
      view = AnyView(MainView(store: store))
    case "time-options", "time-options-minus":
      size = NSSize(width: 360, height: 680)
      view = AnyView(
        FocusControls(store: store))
    case "menu", "menu-ready", "menu-break", "menu-review", "menu-overtime":
      if request.scene == "menu-review" {
        store.completionSessionID = store.data.sessions.first?.id
      }
      size = NSSize(width: 600, height: 480)
      view = AnyView(MenuBarView(store: store))
    case "todos", "todos-empty", "todos-long":
      store.selection = .focus
      if request.scene == "todos-empty" { store.data.todos = [] }
      if request.scene == "todos-long" {
        store.data.todos.append(
          TodoItem(
            title:
              "Review the full onboarding flow and make sure all keyboard shortcuts and accessibility labels work correctly"
          ))
      }
      size = NSSize(width: 880, height: 680)
      view = AnyView(MainView(store: store))
    case "focus-compact":
      store.selection = .focus
      size = NSSize(width: 780, height: 620)
      view = AnyView(MainView(store: store))
    case "focus-wide":
      store.selection = .focus
      size = NSSize(width: 880, height: 680)
      view = AnyView(MainView(store: store))
    case "focus-expanded":
      store.selection = .focus
      size = NSSize(width: 1_100, height: 700)
      view = AnyView(MainView(store: store))
    case "focus-tall":
      store.selection = .focus
      size = NSSize(width: 780, height: 900)
      view = AnyView(MainView(store: store))
    case "dashboard-running", "dashboard-break", "dashboard-calendar", "dashboard-overtime":
      store.selection = .focus
      size = NSSize(width: 880, height: 680)
      view = AnyView(MainView(store: store))
    case "dashboard-previous":
      size = NSSize(width: 420, height: 680)
      view = AnyView(
        FocusDayPanel(
          store: store,
          selectedDate: Calendar.current.date(byAdding: .day, value: -1, to: store.now)!))
    default:
      store.selection = .focus
      size = NSSize(width: 880, height: 680)
      view = AnyView(MainView(store: store))
    }

    let accessibilityFixture = request.scene == "focus-no-animation"
    let hostingView = NSHostingView(
      rootView:
        view
        .transaction { transaction in
          if accessibilityFixture { transaction.disablesAnimations = true }
        }
        .background(
          request.composited
            ? Color.clear
            : request.scene == "reminder-countdown-light" ? .white : IntervalTheme.surface))
    hostingView.frame = NSRect(origin: .zero, size: size)
    let window = SnapshotWindow(
      contentRect: hostingView.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.backgroundColor = request.composited ? .clear : NSColor(IntervalTheme.surface)
    window.isOpaque = !request.composited
    window.hasShadow = false
    window.contentView = hostingView
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
    try await Task.sleep(for: .milliseconds(350))
    hostingView.layoutSubtreeIfNeeded()
    if request.scene == "dashboard-todo-focused",
      let field = descendants(of: hostingView).compactMap({ $0 as? NSTextField }).first(where: {
        $0.accessibilityLabel() == "To-do title"
      })
    {
      window.makeFirstResponder(field)
      try await Task.sleep(for: .milliseconds(100))
    }
    if request.scene == "reminder-editor-bottom" {
      scrollEditorToBottom(in: hostingView)
      hostingView.layoutSubtreeIfNeeded()
      try await Task.sleep(for: .milliseconds(100))
    }
    window.display()
    if request.composited {
      try FileManager.default.createDirectory(
        at: URL(fileURLWithPath: request.path).deletingLastPathComponent(),
        withIntermediateDirectories: true)
      let capture = Process()
      capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
      capture.arguments = ["-x", "-o", "-l", String(window.windowNumber), request.path]
      try capture.run()
      capture.waitUntilExit()
      guard capture.terminationStatus == 0 else { throw CocoaError(.fileWriteUnknown) }
      window.close()
      return
    }
    guard let rep = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
      throw CocoaError(.fileWriteUnknown)
    }
    hostingView.cacheDisplay(in: hostingView.bounds, to: rep)
    guard let png = rep.representation(using: .png, properties: [:]) else {
      throw CocoaError(.fileWriteUnknown)
    }
    let url = URL(fileURLWithPath: request.path)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try png.write(to: url, options: .atomic)
    window.close()
  }

  private static func scrollEditorToBottom(in root: NSView) {
    let scrollViews = descendants(of: root).compactMap { $0 as? NSScrollView }
    guard
      let editor =
        scrollViews
        .filter({ scrollView in
          guard let documentView = scrollView.documentView else { return false }
          return documentView.bounds.height > scrollView.contentView.bounds.height
        })
        .max(by: { $0.bounds.width < $1.bounds.width }),
      let documentView = editor.documentView
    else { return }

    let clipView = editor.contentView
    let bottomY =
      documentView.isFlipped
      ? max(0, documentView.bounds.maxY - clipView.bounds.height)
      : documentView.bounds.minY
    clipView.scroll(to: NSPoint(x: clipView.bounds.origin.x, y: bottomY))
    editor.reflectScrolledClipView(clipView)
  }

  private static func descendants(of view: NSView) -> [NSView] {
    view.subviews.flatMap { [$0] + descendants(of: $0) }
  }
}

private final class SnapshotWindow: NSWindow {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }
}
