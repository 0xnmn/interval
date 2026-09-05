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

    static func fixture(scene: String) -> PersistedData {
        let timerID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        var timer = TimerState(id: timerID, kind: .focus, duration: 1_500, status: .ready)
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
        return PersistedData(activeTimer: timer, scratchpad: "Outline the launch notes\nReview accessibility labels",
            sessions: [session], reminders: [Reminder(title: "Plan tomorrow", dueAt: fixtureNow.addingTimeInterval(3_600))],
            completedFocusCount: 3)
    }

    static func render(request: SnapshotRequest, store: AppStore) async throws {
        let size: NSSize
        let view: AnyView
        switch request.scene {
        case "history": size = NSSize(width: 900, height: 650); view = AnyView(MainView(store: store, selection: .history))
        case "reminders": size = NSSize(width: 900, height: 650); view = AnyView(MainView(store: store, selection: .reminders))
        case "settings": size = NSSize(width: 480, height: 320); view = AnyView(SettingsView(store: store))
        case "sound-settings": size = NSSize(width: 500, height: 370); view = AnyView(SettingsView(store: store, showSound: true))
        case "reflection": store.completionSessionID = store.data.sessions.first?.id; size = NSSize(width: 900, height: 650); view = AnyView(MainView(store: store))
        case "menu": size = NSSize(width: 310, height: 280); view = AnyView(MenuBarView(store: store))
        default: size = NSSize(width: 900, height: 650); view = AnyView(MainView(store: store))
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
