import AppKit
import IntervalCore
import SwiftUI

struct SnapshotRequest {
    let path: String
    let scene: String

    init?(arguments: [String]) {
        guard let index = arguments.firstIndex(of: "--snapshot"), arguments.indices.contains(index + 1) else { return nil }
        path = arguments[index + 1]
        if let sceneIndex = arguments.firstIndex(of: "--snapshot-scene"), arguments.indices.contains(sceneIndex + 1) {
            scene = arguments[sceneIndex + 1]
        } else {
            scene = "focus"
        }
    }
}

@MainActor enum SnapshotRenderer {
    static let fixtureNow = Date(timeIntervalSince1970: 1_800_000_000.125)
    static let calendarFixture = [
        CalendarEventSnapshot(id: "calendar-1", title: "Design review",
            start: fixtureNow.addingTimeInterval(-900), end: fixtureNow.addingTimeInterval(900),
            allDay: false, calendarName: "Work"),
        CalendarEventSnapshot(id: "calendar-2", title: "Team offsite",
            start: Calendar.current.startOfDay(for: fixtureNow),
            end: Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: fixtureNow))!,
            allDay: true, calendarName: "Work"),
        CalendarEventSnapshot(id: "calendar-3", title: "Dinner",
            start: fixtureNow.addingTimeInterval(10_800), end: fixtureNow.addingTimeInterval(14_400),
            allDay: false, calendarName: "Personal")
    ]

    static func fixture(scene: String) -> PersistedData {
        let timerID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        var timer = TimerState(id: timerID, kind: .focus, duration: 1_500, status: .ready)
        if scene == "reflection" { timer = TimerState(id: timerID, kind: .shortBreak, duration: 300, status: .ready) }
        if scene == "paused" || scene == "menu" {
            timer.status = .paused
            timer.startedAt = fixtureNow.addingTimeInterval(-510)
            timer.elapsedBeforePause = 420
        }
        let session = SessionRecord(id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            timerID: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!, kind: .focus,
            startedAt: fixtureNow.addingTimeInterval(-3_600), endedAt: fixtureNow.addingTimeInterval(-2_100),
            plannedDuration: 1_500, activeDuration: 1_500, outcome: .completed,
            feedback: scene == "reflection" ? nil : "focused", journal: "Clear progress on the launch plan.")
        var settings = IntervalSettings()
        if scene == "history" || scene == "calendar-settings" || scene == "history-no-selection" {
            settings.calendarIntegrationEnabled = true; settings.selectedCalendarIDs = ["Work", "Personal"]
            settings.didChooseInitialCalendars = true
        }
        if scene == "history-no-selection" { settings.selectedCalendarIDs = [] }
        let sessions = scene == "history-disabled" || scene == "history-no-selection" ? [] : [session]
        return PersistedData(settings: settings, activeTimer: timer, scratchpad: "Outline the launch notes\nReview accessibility labels",
            sessions: sessions, reminders: [Reminder(title: "Look away", message: "Look at something far away for 20 seconds.", emoji: "👀", intervalSeconds: 600, displaySeconds: 20, dueAt: fixtureNow.addingTimeInterval(600)), Reminder(title: "Water", message: "Take a moment to drink some water.", emoji: "💧", intervalSeconds: 3_600, displaySeconds: 60, presentation: .fullscreen, dueAt: fixtureNow.addingTimeInterval(3_600))],
            completedFocusCount: 3)
    }

    static func render(request: SnapshotRequest, store: AppStore) async throws {
        let size: NSSize
        let view: AnyView
        switch request.scene {
        case "history", "history-disabled", "history-no-selection":
            store.selection = .history; size = NSSize(width: 1000, height: 740); view = AnyView(MainView(store: store))
        case "reminders": store.selection = .reminders; size = NSSize(width: 1000, height: 740); view = AnyView(MainView(store: store))
        case "reminder-editor", "reminder-editor-expanded": size = NSSize(width: 900, height: 650); view = AnyView(RemindersView(store: store, selection: store.data.reminders[0].id, advanced: request.scene.hasSuffix("expanded")))
        case "reminder-countdown", "reminder-countdown-paused":
            let reminder = store.data.reminders[0]; size = NSSize(width: 290, height: 118)
            view = AnyView(ReminderWarningView(reminder: reminder, overlay: .warning(reminderID: reminder.id, remaining: 7, isPaused: request.scene == "reminder-countdown-paused")))
        case "reminder-floating":
            size = NSSize(width: 520, height: 480); view = AnyView(ReminderTakeoverView(reminder: store.data.reminders[0], dismiss: {}, snooze: {}))
        case "reminder-fullscreen":
            size = NSSize(width: 900, height: 650); view = AnyView(ReminderTakeoverView(reminder: store.data.reminders[1], dismiss: {}, snooze: {}))
        case "settings": size = NSSize(width: 520, height: 500); view = AnyView(SettingsView(store: store))
        case "sound-settings": size = NSSize(width: 520, height: 500); view = AnyView(SettingsView(store: store, showSound: true))
        case "calendar-settings": size = NSSize(width: 520, height: 500); view = AnyView(SettingsView(store: store, showCalendar: true))
        case "general-settings": size = NSSize(width: 520, height: 500); view = AnyView(SettingsView(store: store, selectedTab: 3))
        case "updates-settings": size = NSSize(width: 520, height: 500); view = AnyView(SettingsView(store: store, selectedTab: 4))
        case "reflection": store.completionSessionID = store.data.sessions.first?.id; size = NSSize(width: 1000, height: 740); view = AnyView(MainView(store: store))
        case "menu": size = NSSize(width: 310, height: 420); view = AnyView(MenuBarView(store: store))
        default: store.selection = .focus; size = NSSize(width: 1000, height: 740); view = AnyView(MainView(store: store))
        }

        let hostingView = NSHostingView(rootView: view.background(Color(nsColor: .windowBackgroundColor)))
        hostingView.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hostingView.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.backgroundColor = .windowBackgroundColor
        window.isOpaque = true
        window.hasShadow = false
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        try await Task.sleep(for: .milliseconds(350))
        hostingView.layoutSubtreeIfNeeded()
        window.display()
        guard let rep = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            throw CocoaError(.fileWriteUnknown)
        }
        hostingView.cacheDisplay(in: hostingView.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        let url = URL(fileURLWithPath: request.path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: url, options: .atomic)
        window.close()
    }
}
