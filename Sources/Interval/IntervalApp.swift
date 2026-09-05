import AppKit
import IntervalCore
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    static var snapshotRequest: SnapshotRequest?
    static var snapshotStore: AppStore?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let request = Self.snapshotRequest, let store = Self.snapshotStore else { return }
        Task { @MainActor in
            do { try await SnapshotRenderer.render(request: request, store: store) }
            catch { fputs("Snapshot failed: \(error)\n", stderr) }
            NSApp.terminate(nil)
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main
struct IntervalApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store: AppStore

    init() {
        if let request = SnapshotRequest(arguments: CommandLine.arguments) {
            let ephemeral = FileManager.default.temporaryDirectory
                .appendingPathComponent("interval-snapshot-\(UUID().uuidString).json")
            let snapshotStore = AppStore(persistence: JSONStore(fileURL: ephemeral))
            snapshotStore.data = SnapshotRenderer.fixture(scene: request.scene)
            snapshotStore.now = SnapshotRenderer.fixtureNow
            _store = State(initialValue: snapshotStore)
            AppDelegate.snapshotRequest = request
            AppDelegate.snapshotStore = snapshotStore
        } else {
            _store = State(initialValue: AppStore())
        }
    }
    var body: some Scene {
        Window("Interval", id: "main") { MainView(store: store) }
            .defaultSize(width: 900, height: 650)
            .windowResizability(.contentMinSize)
        MenuBarExtra { MenuBarView(store: store) } label: {
            Label(durationString(store.remaining), systemImage: store.timer.status == .running ? "timer" : "timer.circle")
        }.menuBarExtraStyle(.window)
        Settings { SettingsView(store: store) }
    }
}
