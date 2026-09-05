import AppKit
import IntervalCore
import SwiftUI

struct SnapshotRequest {
  let path: String
  let scene: String
  let composited: Bool

  init?(arguments: [String]) {
    guard let index = arguments.firstIndex(of: "--snapshot"), arguments.indices.contains(index + 1)
    else { return nil }
    path = arguments[index + 1]
    composited = arguments.contains("--snapshot-composited")
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
    let timerID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    var timer = TimerState(id: timerID, kind: .focus, duration: 1_500, status: .ready)
    if scene.hasPrefix("reflection") {
      timer = TimerState(
        id: timerID, kind: .shortBreak, duration: 300, status: .ready)
    }
    if scene == "dashboard-running" || scene == "menu" || scene == "time-options"
      || scene == "time-options-minus"
    {
      timer.status = .running
      timer.startedAt = fixtureNow.addingTimeInterval(-420)
      timer.deadline = fixtureNow.addingTimeInterval(1_080)
    }
    if scene == "dashboard-break" {
      timer = TimerState(
        id: timerID, kind: .shortBreak, duration: 300, status: .running,
        startedAt: fixtureNow.addingTimeInterval(-60),
        deadline: fixtureNow.addingTimeInterval(240))
    }
    var session = SessionRecord(
      id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
      timerID: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!, kind: .focus,
      startedAt: fixtureNow.addingTimeInterval(-3_600),
      endedAt: fixtureNow.addingTimeInterval(-2_100),
      plannedDuration: 1_500, activeDuration: 1_500, outcome: .completed,
      feedback: scene == "reflection" ? nil : "focused",
      journal: "Clear progress on the launch plan.")
    if scene == "history-legacy" {
      session.outcome = .abandoned
      session.isDurationEstimated = true
    }
    var settings = IntervalSettings()
    if scene == "history" || scene == "calendar-settings" || scene == "history-no-selection"
      || scene == "dashboard-calendar"
    {
      settings.calendarIntegrationEnabled = true
      settings.selectedCalendarIDs = ["Work", "Personal"]
      settings.didChooseInitialCalendars = true
    }
    if scene == "history-no-selection" { settings.selectedCalendarIDs = [] }
    let sessions = scene == "history-disabled" || scene == "history-no-selection" ? [] : [session]
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
    return PersistedData(
      settings: settings, activeTimer: timer,
      scratchpad: "Outline the launch notes\nReview accessibility labels",
      sessions: sessions,
      reminders: reminders,
      completedFocusCount: 3)
  }

  static func render(request: SnapshotRequest, store: AppStore) async throws {
    let size: NSSize
    let view: AnyView
    if request.scene == "dashboard-calendar" {
      store.calendarService.configure(
        enabled: true, selectedCalendarIDs: store.data.settings.selectedCalendarIDs)
      _ = store.calendarService.hasEvent(at: fixtureNow)
    }
    switch request.scene {
    case "history", "history-disabled", "history-no-selection":
      store.selection = .history
      size = NSSize(width: 880, height: 680)
      view = AnyView(MainView(store: store))
    case "history-legacy":
      size = NSSize(width: 580, height: 650)
      view = AnyView(
        VStack {
          SessionRow(session: store.data.sessions[0]).padding()
          SessionInspector(store: store, session: store.data.sessions[0])
        })
    case "reminders", "reminders-empty":
      store.selection = .reminders
      size = NSSize(width: 880, height: 680)
      view = AnyView(MainView(store: store))
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
      size = NSSize(width: 520, height: 480)
      view = AnyView(
        ReminderTakeoverView(reminder: store.data.reminders[0], dismiss: {}, snooze: {}))
    case "reminder-fullscreen":
      size = NSSize(width: 900, height: 650)
      view = AnyView(
        ReminderTakeoverView(reminder: store.data.reminders[1], dismiss: {}, snooze: {}))
    case "settings":
      size = NSSize(width: 560, height: 450)
      view = AnyView(SettingsView(store: store))
    case "sound-settings":
      size = NSSize(width: 560, height: 450)
      view = AnyView(SettingsView(store: store, showSound: true))
    case "calendar-settings":
      size = NSSize(width: 560, height: 450)
      view = AnyView(SettingsView(store: store, showCalendar: true))
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
        FocusControls(store: store, adjustmentDirection: request.scene == "time-options" ? 1 : -1))
    case "menu":
      size = NSSize(width: 348, height: 290)
      view = AnyView(MenuBarView(store: store))
    case "notes", "notes-empty":
      store.selection = .focus
      if request.scene == "notes-empty" { store.data.scratchpad = "" }
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
    case "dashboard-running", "dashboard-break", "dashboard-calendar":
      store.selection = .focus
      size = NSSize(width: 880, height: 680)
      view = AnyView(MainView(store: store))
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
        .preferredColorScheme(.dark)
        .background(
          request.composited
            ? Color.clear
            : request.scene == "reminder-countdown-light" ? .white : IntervalTheme.surface))
    hostingView.frame = NSRect(origin: .zero, size: size)
    let window = SnapshotWindow(
      contentRect: hostingView.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: .darkAqua)
    window.backgroundColor = request.composited ? .clear : NSColor(IntervalTheme.surface)
    window.isOpaque = !request.composited
    window.hasShadow = false
    window.contentView = hostingView
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
    try await Task.sleep(for: .milliseconds(350))
    hostingView.layoutSubtreeIfNeeded()
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
