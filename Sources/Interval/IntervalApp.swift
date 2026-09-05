import AppKit
import IntervalCore
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
  static var snapshotRequest: SnapshotRequest?
  static var snapshotStore: AppStore?
  static var snapshotURL: URL?

  func applicationDidFinishLaunching(_ notification: Notification) {
    guard let request = Self.snapshotRequest, let store = Self.snapshotStore else { return }
    Task { @MainActor in
      do { try await SnapshotRenderer.render(request: request, store: store) } catch {
        fputs("Snapshot failed: \(error)\n", stderr)
      }
      NSApp.terminate(nil)
    }
  }
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
  func applicationWillTerminate(_ notification: Notification) {
    Self.snapshotStore?.checkpointForTermination()
    if let snapshotURL = Self.snapshotURL { try? FileManager.default.removeItem(at: snapshotURL) }
  }
}

@main
struct IntervalApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
  @State private var store: AppStore

  init() {
    if let request = SnapshotRequest(arguments: CommandLine.arguments) {
      let ephemeral = FileManager.default.temporaryDirectory
        .appendingPathComponent("interval-snapshot-\(UUID().uuidString).json")
      let snapshotStore = AppStore(
        persistence: JSONStore(fileURL: ephemeral),
        calendarService: CalendarService(fixtureEvents: SnapshotRenderer.calendarFixture),
        runtimeEnabled: false)
      snapshotStore.data = SnapshotRenderer.fixture(scene: request.scene)
      snapshotStore.calendarService.configure(
        enabled: snapshotStore.data.settings.calendarIntegrationEnabled,
        selectedCalendarIDs: snapshotStore.data.settings.selectedCalendarIDs)
      snapshotStore.calendarService.show(month: SnapshotRenderer.fixtureNow)
      snapshotStore.now = SnapshotRenderer.fixtureNow
      _store = State(initialValue: snapshotStore)
      AppDelegate.snapshotRequest = request
      AppDelegate.snapshotStore = snapshotStore
      AppDelegate.snapshotURL = ephemeral
    } else {
      _store = State(initialValue: AppStore())
    }
    AppDelegate.snapshotStore = _store.wrappedValue
  }
  var body: some Scene {
    Window("Interval", id: "main") { MainView(store: store) }
      .defaultSize(width: 420, height: 520)
      .windowStyle(.hiddenTitleBar)
      .windowResizability(.contentMinSize)
    MenuBarExtra {
      MenuBarView(store: store)
    } label: {
      Label(
        durationString(store.remaining),
        systemImage: store.timer.status == .running ? "timer" : "timer.circle")
    }.menuBarExtraStyle(.window)
    Settings { SettingsView(store: store) }
      .commands {
        CommandGroup(after: .newItem) {
          Button("Start or Pause Cycle") { store.startOrToggle() }.keyboardShortcut(
            "s", modifiers: [.command, .shift])
          Divider()
          Button("Focus") { store.selection = .focus }.keyboardShortcut("1")
          Button("Stats") { store.selection = .history }.keyboardShortcut("2")
          Button("Reminders") { store.selection = .reminders }.keyboardShortcut("3")
        }
        CommandGroup(after: .appInfo) {
          Button("Check for Updates…") { store.updates.checkNow() }.disabled(
            !store.updates.isConfigured)
        }
      }
  }
}
