import AppKit
import IntervalCore
import Testing

@testable import Interval

@MainActor @Suite("Quick panels", .serialized)
struct QuickPanelTests {
  @Test func geometryKeepsContentBelowCutoutOnOffsetScreens() {
    let screen = NSRect(x: -1512, y: 140, width: 1512, height: 982)
    let geometry = NotchGeometry(hasHardwareNotch: true, cutoutWidth: 180, topInset: 32)
    for expanded in [false, true] {
      let frame = geometry.frame(expanded: expanded, in: screen)
      #expect(frame.midX == screen.midX)
      #expect(frame.maxY == screen.maxY)
      #expect(screen.contains(frame))
    }
    #expect(geometry.frame(expanded: true, in: screen).height == 512)
    #expect(NotchGeometry.fallback.compactSize.height == 32)
  }

  @Test func settingsMigrateAndRoundTrip() throws {
    let legacy = Data(
      "{\"focusMinutes\":25,\"shortBreakMinutes\":5,\"longBreakMinutes\":10,\"longBreakEvery\":4}"
        .utf8)
    let old = try JSONDecoder().decode(IntervalSettings.self, from: legacy)
    #expect(old.notchEnabled)
    #expect(old.completionPopupEnabled)
    let settings = IntervalSettings(notchEnabled: true, completionPopupEnabled: false).clamped()
    #expect(
      try JSONDecoder().decode(IntervalSettings.self, from: JSONEncoder().encode(settings))
        == settings)
  }

  @Test func completionIsNotRepeatedAfterEscapeButCanResumeTemporaryHide() throws {
    let store = makeStore()
    defer { try? FileManager.default.removeItem(at: store.storageURL.deletingLastPathComponent()) }
    store.data = SnapshotRenderer.fixture(scene: "menu-review")
    store.completionSessionID = store.data.sessions.first?.id
    let controller = SessionCompletionController()
    defer { controller.close() }
    let original = Set(NSApp.windows.map(\.windowNumber))
    controller.update(store: store)
    let panel = try #require(
      NSApp.windows.first { !original.contains($0.windowNumber) && $0.isVisible })
    #expect(!panel.isKeyWindow)
    controller.close()
    controller.update(store: store)
    let resumed = try #require(
      NSApp.windows.first { !original.contains($0.windowNumber) && $0.isVisible })
    resumed.cancelOperation(nil)
    controller.update(store: store)
    #expect(!NSApp.windows.contains { !original.contains($0.windowNumber) && $0.isVisible })
    #expect(store.completionSessionID != nil)
  }

  @Test func nativeNotchHoverExpandsAndEscapeCollapses() async throws {
    let store = makeStore()
    defer { try? FileManager.default.removeItem(at: store.storageURL.deletingLastPathComponent()) }
    store.data.settings.notchEnabled = true
    let controller = NotchController()
    defer { controller.close() }
    let original = Set(NSApp.windows.map(\.windowNumber))
    controller.update(store: store)
    let panel = try #require(
      NSApp.windows.first { !original.contains($0.windowNumber) && $0.isVisible })
    let initialFrame = panel.frame
    #expect(!panel.isKeyWindow)
    let event = try #require(
      NSEvent.enterExitEvent(
        with: .mouseEntered, location: .zero, modifierFlags: [], timestamp: 0,
        windowNumber: panel.windowNumber, context: nil, eventNumber: 0, trackingNumber: 0,
        userData: nil))
    panel.contentView?.mouseEntered(with: event)
    for _ in 0..<40 {
      if panel.frame.width == 600 { break }
      try await Task.sleep(for: .milliseconds(50))
    }
    #expect(panel.frame.width == 600)
    #expect(panel.frame.maxY == initialFrame.maxY)
    #expect(!panel.isKeyWindow)
    let exit = try #require(
      NSEvent.enterExitEvent(
        with: .mouseExited, location: .zero, modifierFlags: [], timestamp: 0,
        windowNumber: panel.windowNumber, context: nil, eventNumber: 1, trackingNumber: 0,
        userData: nil))
    panel.contentView?.mouseExited(with: exit)
    try await Task.sleep(for: .milliseconds(800))
    #expect(panel.frame == initialFrame)
    panel.contentView?.mouseEntered(with: event)
    try await Task.sleep(for: .milliseconds(300))
    panel.cancelOperation(nil)
    try await Task.sleep(for: .milliseconds(300))
    #expect(panel.frame == initialFrame)
    store.data.settings.notchEnabled = false
    controller.update(store: store)
    #expect(!panel.isVisible)
  }

  private func makeStore() -> AppStore {
    _ = NSApplication.shared
    return AppStore(
      persistence: JSONStore(
        fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
          .appendingPathComponent("state.json")), runtimeEnabled: false)
  }
}
