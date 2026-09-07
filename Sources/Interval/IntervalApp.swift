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
      .defaultSize(width: 880, height: 680)
      .windowStyle(.hiddenTitleBar)
      .windowResizability(.contentMinSize)
    MenuBarExtra {
      MenuBarView(store: store)
    } label: {
      Label(
        store.timerText,
        systemImage: store.timer.status == .running ? "timer" : "timer.circle")
    }.menuBarExtraStyle(.window)
    Settings { SettingsView(store: store) }
      .commands { IntervalCommands(store: store) }
  }
}

struct IntervalCommands: Commands {
  @Bindable var store: AppStore
  @Environment(\.openWindow) private var openWindow

  var body: some Commands {
    CommandGroup(after: .newItem) {
      Button(
        store.timer.kind == .focus
          ? "Start session" : store.timer.status == .ready ? "Start break" : "Resume focus"
      ) {
        if store.timer.status == .ready { store.startSession() } else { store.endBreak() }
      }.keyboardShortcut("s", modifiers: [.command, .shift])
        .disabled(store.timer.kind == .focus && store.timer.status != .ready)
      Button("Take a break") {
        if store.timer.status == .ready { store.startBreakNow() } else { confirm(.takeBreak) }
      }.keyboardShortcut("b", modifiers: [.command, .shift])
        .disabled(store.timer.kind != .focus)
      Button("Abandon…") { confirm(.abandon) }
        .keyboardShortcut("x", modifiers: [.command, .shift])
        .disabled(store.timer.status != .running && !store.breakEnded)
      Menu("Adjust time") {
        Button("+5 min") { store.adjustCurrentTime(by: 300) }
          .keyboardShortcut("=", modifiers: [.command, .option])
          .disabled(store.timer.duration >= 3600)
        Button("−5 min") { store.adjustCurrentTime(by: -300) }
          .keyboardShortcut("-", modifiers: [.command, .option])
          .disabled(store.remaining <= 60)
        ForEach([10, 15], id: \.self) { minutes in
          Button("+\(minutes) min") { store.adjustCurrentTime(by: Double(minutes * 60)) }
            .disabled(store.timer.duration >= 3600)
          Button("−\(minutes) min") { store.adjustCurrentTime(by: -Double(minutes * 60)) }
            .disabled(store.remaining <= 60)
        }
      }.disabled(store.timer.status != .ready && store.timer.status != .running)
      Divider()
      Button("Focus") { show(.focus) }.keyboardShortcut("1")
      Button("Stats") { show(.history) }.keyboardShortcut("2")
      Button("Reminders") { show(.reminders) }.keyboardShortcut("3")
      Button("Open notch panel") { store.openNotchFromKeyboard() }
        .keyboardShortcut("n", modifiers: [.command, .shift])
        .disabled(!store.canOpenNotch)
    }
    CommandGroup(after: .appInfo) {
      Button("Check for updates…") { store.updates.checkNow() }.disabled(
        !store.updates.isConfigured)
    }
  }

  private func show(_ destination: Destination) {
    store.selection = destination
    openWindow(id: "main")
    NSApp.activate(ignoringOtherApps: true)
  }

  private func confirm(_ action: AppStore.TimerConfirmation) {
    show(store.selection ?? .focus)
    store.pendingTimerConfirmation = action
  }
}
