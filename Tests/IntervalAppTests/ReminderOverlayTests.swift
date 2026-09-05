import AppKit
import IntervalCore
import Testing

@testable import Interval

@MainActor @Suite("Cursor warning", .serialized)
struct ReminderOverlayTests {
  @Test func warningReusesHostingViewAndReleasesController() throws {
    _ = NSApplication.shared
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = AppStore(
      persistence: JSONStore(fileURL: directory.appendingPathComponent("data.json")),
      runtimeEnabled: false)
    let reminder = Reminder(title: "Look away")
    let existing = Set(NSApp.windows.map(\.windowNumber))
    var controller: ReminderOverlayController? = ReminderOverlayController()
    weak var weakController = controller
    controller?.update(
      .warning(reminderID: reminder.id, remaining: 10, isPaused: false), reminder: reminder,
      store: store)
    let panel = try #require(
      NSApp.windows.first { !existing.contains($0.windowNumber) } as? NSPanel)
    let host = try #require(panel.contentView)
    #expect(panel.ignoresMouseEvents)
    #expect(!panel.isOpaque)
    #expect(!panel.hasShadow)
    for remaining in [9.9, 9.5, 9.0, 8.75] {
      controller?.update(
        .warning(reminderID: reminder.id, remaining: remaining, isPaused: true), reminder: reminder,
        store: store)
      #expect(panel.contentView === host)
    }
    controller?.close()
    #expect(!panel.isVisible)
    controller = nil
    #expect(weakController == nil)
  }

  @Test func cursorMovesBetweenReminderTicksAndStopsOnClose() async throws {
    _ = NSApplication.shared
    let screen = try #require(NSScreen.main)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = AppStore(
      persistence: JSONStore(fileURL: directory.appendingPathComponent("data.json")),
      runtimeEnabled: false)
    let reminder = Reminder(title: "Look away")
    var samples = 0
    let controller = ReminderOverlayController {
      samples += 1
      return NSPoint(x: screen.visibleFrame.midX + CGFloat(samples), y: screen.visibleFrame.midY)
    }
    defer { controller.close() }
    let existing = Set(NSApp.windows.map(\.windowNumber))
    controller.update(
      .warning(reminderID: reminder.id, remaining: 10, isPaused: false), reminder: reminder,
      store: store)
    let panel = try #require(NSApp.windows.first { !existing.contains($0.windowNumber) })
    let initialOrigin = panel.frame.origin
    // No reminder update calls: movement must be driven by display refresh, not the 250ms ticker.
    try await Task.sleep(for: .milliseconds(200))
    #expect(samples > 2)
    #expect(panel.frame.origin != initialOrigin)
    controller.close()
    let stoppedSamples = samples
    try await Task.sleep(for: .milliseconds(100))
    #expect(samples == stoppedSamples)
  }
}
