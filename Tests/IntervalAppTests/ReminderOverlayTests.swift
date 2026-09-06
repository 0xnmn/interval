import AppKit
import IntervalCore
import Testing

@testable import Interval

@MainActor @Suite("Cursor warning", .serialized)
struct ReminderOverlayTests {
  @Test func fullscreenReminderCoversEveryDisplayWithNativeTakeoverPanels() throws {
    _ = NSApplication.shared
    let originalPolicy = NSApp.activationPolicy()
    defer { NSApp.setActivationPolicy(originalPolicy) }
    #expect(NSApp.setActivationPolicy(.regular))
    let screens = NSScreen.screens
    #expect(!screens.isEmpty)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = AppStore(
      persistence: JSONStore(fileURL: directory.appendingPathComponent("data.json")),
      runtimeEnabled: false)
    let reminder = Reminder(title: "Look away", presentation: .fullscreen)
    let existing = Set(NSApp.windows.map(\.windowNumber))
    let controller = ReminderOverlayController()
    defer { controller.close() }

    controller.update(
      .reminder(reminderID: reminder.id, shownAt: Date()), reminder: reminder, store: store)
    let panels = NSApp.windows.compactMap { window -> NSPanel? in
      guard !existing.contains(window.windowNumber) else { return nil }
      return window as? NSPanel
    }

    #expect(panels.count == screens.count)
    #expect(NSApp.activationPolicy() == .accessory)
    for screen in screens {
      let panel = try #require(panels.first { $0.frame == screen.frame })
      #expect(panel.level == .screenSaver)
      #expect(panel.styleMask == [.borderless, .nonactivatingPanel])
      #expect(!panel.styleMask.contains(.fullScreen))
      #expect(!panel.hasShadow)
      #expect(!panel.hidesOnDeactivate)
      #expect(panel.isFloatingPanel)
      #expect(!panel.isMovable)
      #expect(panel.collectionBehavior.contains(.canJoinAllApplications))
      #expect(panel.collectionBehavior.contains(.canJoinAllSpaces))
      #expect(panel.collectionBehavior.contains(.fullScreenAuxiliary))
      #expect(panel.collectionBehavior.contains(.stationary))
      #expect(panel.collectionBehavior.contains(.ignoresCycle))
    }

    NotificationCenter.default.post(
      name: NSApplication.didChangeScreenParametersNotification,
      object: NSApp)
    #expect(panels.allSatisfy { !$0.isVisible })
    let rebuilt = NSApp.windows.filter { $0.isVisible && $0.level == .screenSaver }
    #expect(rebuilt.count == screens.count)
    #expect(screens.allSatisfy { screen in rebuilt.contains { $0.frame == screen.frame } })
    #expect(NSApp.activationPolicy() == .accessory)
    controller.close()
    #expect(NSApp.activationPolicy() == .regular)
    #expect(rebuilt.allSatisfy { !$0.isVisible })
  }

  @Test func floatingReminderUsesCursorDisplayAndCloseRemovesItsPanel() throws {
    _ = NSApplication.shared
    let screen = try #require(NSScreen.screens.last)
    let cursor = NSPoint(x: screen.frame.midX, y: screen.frame.midY)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = AppStore(
      persistence: JSONStore(fileURL: directory.appendingPathComponent("data.json")),
      runtimeEnabled: false)
    let reminder = Reminder(title: "Look away", presentation: .floating)
    let existing = Set(NSApp.windows.map(\.windowNumber))
    let controller = ReminderOverlayController(cursorLocation: { cursor })
    controller.update(
      .reminder(reminderID: reminder.id, shownAt: Date()), reminder: reminder, store: store)
    let panel = try #require(
      NSApp.windows.first { !existing.contains($0.windowNumber) } as? NSPanel)
    let expected = NSRect(
      x: screen.visibleFrame.midX - 260, y: screen.visibleFrame.midY - 240,
      width: 520, height: 480)

    #expect(panel.frame == expected)
    #expect(panel.level == .floating)
    #expect(panel.styleMask == [.borderless, .nonactivatingPanel])
    #expect(!panel.styleMask.contains(.fullScreen))
    #expect(panel.hasShadow)
    controller.close()
    #expect(!panel.isVisible)
  }

  @Test(arguments: [ReminderPresentation.floating, .fullscreen])
  func escapeDismissesPreviewWithoutChangingReminderSchedule(presentation: ReminderPresentation)
    throws
  {
    _ = NSApplication.shared
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = AppStore(
      persistence: JSONStore(fileURL: directory.appendingPathComponent("data.json")),
      runtimeEnabled: false)
    var reminder = Reminder(title: "Look away", presentation: presentation)
    reminder.dueAt = Date(timeIntervalSince1970: 12_345)
    store.data.reminders = [reminder]
    let before = store.data.reminders
    store.previewReminder(reminder.id)
    let controller = ReminderOverlayController()
    defer { controller.close() }
    let existing = Set(NSApp.windows.map(\.windowNumber))
    controller.update(store.reminderOverlay, reminder: reminder, store: store)
    let panel = try #require(
      NSApp.windows.first { !existing.contains($0.windowNumber) } as? NSPanel)

    let escape = try #require(
      NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
        windowNumber: panel.windowNumber, context: nil, characters: "\u{1b}",
        charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
    panel.sendEvent(escape)

    #expect(store.reminderOverlay == nil)
    #expect(store.data.reminders == before)
    controller.close()
    #expect(!panel.isVisible)
  }

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
