import AppKit
import IntervalCore
import SwiftUI
import Testing

@testable import Interval

@MainActor @Suite("Cursor warning", .serialized)
struct ReminderOverlayTests {
  @Test(arguments: [60.0, 300.0])
  func fullscreenTimeButtonsDeferOnlyThisOccurrence(seconds: TimeInterval) throws {
    _ = NSApplication.shared
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = AppStore(
      persistence: JSONStore(fileURL: directory.appendingPathComponent("data.json")),
      runtimeEnabled: false)
    let now = Date()
    let reminder = Reminder(
      title: "Look away", intervalSeconds: 600, displaySeconds: 20,
      presentation: .fullscreen, dueAt: now.addingTimeInterval(-10))
    store.data.reminders = [reminder]
    store.reminderOverlay = .reminder(reminderID: reminder.id, shownAt: now.addingTimeInterval(-6))
    let controller = ReminderOverlayController(wallpaperForScreen: { _ in nil })
    defer { controller.close() }
    let existing = Set(NSApp.windows.map(\.windowNumber))
    controller.update(store.reminderOverlay, reminder: reminder, store: store)
    let panel = try #require(NSApp.windows.first { !existing.contains($0.windowNumber) })
    let host = try #require(panel.contentView as? NSHostingView<ReminderTakeoverView>)
    let before = Date()
    host.rootView.extend(seconds)
    let due = try #require(store.data.reminders[0].snoozedUntil)
    #expect(due >= before.addingTimeInterval(seconds))
    #expect(due <= Date().addingTimeInterval(seconds))
    #expect(store.data.reminders[0].intervalSeconds == 600)
    #expect(store.reminderOverlay == nil)
  }

  @Test func doubleEscapeRequiresTwoPressesAfterSkipGate() {
    let start = Date(timeIntervalSince1970: 1000)
    var shortcut = ReminderSkipShortcut()
    let results = [4.8, 5, 5.5, 6, 8, 8.5].map {
      shortcut.press(at: start.addingTimeInterval($0), shownAt: start)
    }
    #expect(results == [false, false, true, false, false, true])
  }

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
    var wallpaperScreens: [NSScreen] = []
    let wallpapers = screens.map { _ in NSImage(size: NSSize(width: 100, height: 100)) }
    let controller = ReminderOverlayController(wallpaperForScreen: { screen in
      wallpaperScreens.append(screen)
      return wallpapers[screens.firstIndex(of: screen)!]
    })
    defer { controller.close() }

    controller.update(
      .reminder(reminderID: reminder.id, shownAt: Date()), reminder: reminder, store: store)
    let panels = NSApp.windows.compactMap { window -> NSPanel? in
      guard !existing.contains(window.windowNumber) else { return nil }
      return window as? NSPanel
    }

    #expect(panels.count == screens.count)
    #expect(wallpaperScreens == screens)
    #expect(NSApp.activationPolicy() == .accessory)
    for screen in screens {
      let panel = try #require(panels.first { $0.frame == screen.frame })
      let host = try #require(panel.contentView as? NSHostingView<ReminderTakeoverView>)
      #expect(host.rootView.wallpaper === wallpapers[screens.firstIndex(of: screen)!])
      #expect(host.safeAreaRegions.isEmpty)
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
    let expected = ReminderOverlayController.floatingFrame(
      size: ReminderOverlayController.floatingSize(for: reminder), in: screen.visibleFrame,
      position: .center)

    #expect(panel.frame == expected)
    #expect(panel.level == .floating)
    #expect(panel.styleMask == [.borderless, .nonactivatingPanel])
    #expect(!panel.styleMask.contains(.fullScreen))
    #expect(panel.hasShadow)
    #expect(panel.isMovable)
    #expect(panel.isMovableByWindowBackground)
    controller.close()
    #expect(!panel.isVisible)
  }

  @Test(arguments: ReminderPosition.allCases)
  func floatingGeometryUsesVisibleFrameAndSelectedPosition(position: ReminderPosition) {
    let visible = NSRect(x: -1440, y: 25, width: 1400, height: 875)
    let size = NSSize(width: 480, height: 300)
    let frame = ReminderOverlayController.floatingFrame(
      size: size, in: visible, position: position)
    let expectedOrigins: [ReminderPosition: NSPoint] = [
      .topLeft: NSPoint(x: -1416, y: 576),
      .topRight: NSPoint(x: -544, y: 576),
      .bottomLeft: NSPoint(x: -1416, y: 49),
      .bottomRight: NSPoint(x: -544, y: 49),
      .center: NSPoint(x: -980, y: 312.5),
    ]
    #expect(frame == NSRect(origin: expectedOrigins[position]!, size: size))
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

    #expect(store.reminderOverlay != nil)
    if case .reminder(let id, let shownAt) = store.reminderOverlay {
      store.dismissReminder(id, at: shownAt.addingTimeInterval(5))
    }

    #expect(store.reminderOverlay == nil)
    #expect(store.data.reminders == before)
    controller.close()
    #expect(!panel.isVisible)
  }

  @Test func cuePlaysOnceForOccurrenceAndNotForWarningOrDisplayRebuild() {
    _ = NSApplication.shared
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = AppStore(
      persistence: JSONStore(fileURL: directory.appendingPathComponent("data.json")),
      runtimeEnabled: false)
    let reminder = Reminder(title: "Look away", sound: .ping)
    var cues: [ReminderSound] = []
    let controller = ReminderOverlayController(playCue: { cues.append($0) })
    defer { controller.close() }
    controller.update(
      .warning(reminderID: reminder.id, remaining: 1, isPaused: false), reminder: reminder,
      store: store)
    #expect(cues.isEmpty)
    let shownAt = Date()
    controller.update(
      .reminder(reminderID: reminder.id, shownAt: shownAt), reminder: reminder, store: store)
    controller.update(
      .reminder(reminderID: reminder.id, shownAt: shownAt), reminder: reminder, store: store)
    NotificationCenter.default.post(
      name: NSApplication.didChangeScreenParametersNotification, object: NSApp)
    #expect(cues == [.ping])
    controller.update(
      .reminder(reminderID: reminder.id, shownAt: shownAt.addingTimeInterval(60)),
      reminder: reminder, store: store)
    #expect(cues == [.ping, .ping])
  }

  @Test func dismissRequiresActiveReminderAndFiveSeconds() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = AppStore(
      persistence: JSONStore(fileURL: directory.appendingPathComponent("data.json")),
      runtimeEnabled: false)
    var reminder = Reminder(title: "Look away")
    let dueAt = Date(timeIntervalSince1970: 10_000)
    reminder.dueAt = dueAt
    store.data.reminders = [reminder]
    let shownAt = Date(timeIntervalSince1970: 20_000)

    store.reminderOverlay = .warning(reminderID: reminder.id, remaining: 1, isPaused: false)
    store.dismissReminder(reminder.id, at: shownAt.addingTimeInterval(10))
    #expect(store.data.reminders[0].dueAt == dueAt)
    store.reminderOverlay = .reminder(reminderID: reminder.id, shownAt: shownAt)
    store.dismissReminder(reminder.id, at: shownAt.addingTimeInterval(4.99))
    #expect(store.reminderOverlay != nil)
    #expect(store.data.reminders[0].dueAt == dueAt)
    store.dismissReminder(reminder.id, at: shownAt.addingTimeInterval(5))
    #expect(store.reminderOverlay == nil)
    // Preserve the recurrence anchor, coalescing missed intervals into the next future slot.
    #expect(store.data.reminders[0].dueAt == dueAt.addingTimeInterval(9 * reminder.intervalSeconds))
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
    for _ in 0..<20 {
      if samples > 2 { break }
      try await Task.sleep(for: .milliseconds(50))
    }
    #expect(samples > 2)
    #expect(panel.frame.origin != initialOrigin)
    controller.close()
    let stoppedSamples = samples
    try await Task.sleep(for: .milliseconds(100))
    #expect(samples == stoppedSamples)
  }
}
