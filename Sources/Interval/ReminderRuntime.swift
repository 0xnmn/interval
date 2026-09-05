import AppKit
import CoreGraphics
import IntervalCore
import QuartzCore
import SwiftUI

enum UserIdleMonitor {
  static var idleSeconds: TimeInterval {
    let types: [CGEventType] = [
      .keyDown, .keyUp, .mouseMoved, .leftMouseDown, .leftMouseUp,
      .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp, .leftMouseDragged,
      .rightMouseDragged, .otherMouseDragged, .scrollWheel,
    ]
    return types.map {
      CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0)
    }.min() ?? 0
  }
}

@MainActor final class ReminderOverlayController: NSObject {
  private var panels: [NSPanel] = []
  private var shown: ReminderOverlay?
  private var shownReminder: Reminder?
  private var warningHost: NSHostingView<ReminderWarningView>?
  private var cursorDisplayLink: CADisplayLink?
  private let cursorLocation: () -> NSPoint

  init(cursorLocation: @escaping () -> NSPoint = { NSEvent.mouseLocation }) {
    self.cursorLocation = cursorLocation
    super.init()
  }

  deinit { cursorDisplayLink?.invalidate() }

  func update(_ overlay: ReminderOverlay?, reminder: Reminder?, store: AppStore) {
    guard let overlay, let reminder else {
      close()
      return
    }
    if case .warning(_, let remaining, let paused) = overlay,
      case .warning(_, let previousRemaining, let previousPaused) = shown
    {
      if reminder != shownReminder || ceil(remaining) != ceil(previousRemaining)
        || paused != previousPaused
      {
        warningHost?.rootView = ReminderWarningView(reminder: reminder, overlay: overlay)
      }
      shown = overlay
      shownReminder = reminder
      return
    }
    guard overlay != shown else { return }
    close()
    shown = overlay
    shownReminder = reminder
    switch overlay {
    case .warning:
      let panel = NSPanel(
        contentRect: NSRect(x: 0, y: 0, width: 250, height: 64),
        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
      configure(panel)
      panel.hasShadow = false
      panel.level = .floating
      let host = NSHostingView(
        rootView: ReminderWarningView(reminder: reminder, overlay: overlay))
      warningHost = host
      panel.contentView = host
      panel.ignoresMouseEvents = true
      panels = [panel]
      positionWarning()
      panel.orderFrontRegardless()
      let target = CursorFrameTarget { [weak self] in self?.positionWarning() }
      let link = panel.displayLink(target: target, selector: #selector(CursorFrameTarget.frame))
      link.add(to: .main, forMode: .common)
      cursorDisplayLink = link
    case .reminder:
      let cursor = NSEvent.mouseLocation
      let cursorScreen =
        NSScreen.screens.first(where: { $0.frame.contains(cursor) }) ?? NSScreen.main
      let screens =
        reminder.presentation == .fullscreen ? NSScreen.screens : [cursorScreen].compactMap { $0 }
      panels = screens.map { screen in
        let rect =
          reminder.presentation == .fullscreen
          ? safeFrame(for: screen)
          : centered(size: NSSize(width: 520, height: 480), in: screen.visibleFrame)
        let panel = EscapePanel(
          contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
          defer: false)
        configure(panel)
        panel.level = .floating
        panel.contentView = NSHostingView(
          rootView: ReminderTakeoverView(
            reminder: reminder,
            dismiss: { store.dismissReminder(reminder.id) },
            snooze: { store.snoozeReminder(reminder.id) }))
        panel.onEscape = { store.dismissReminder(reminder.id) }
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.sharingType = .none
        if screen == cursorScreen {
          panel.makeKeyAndOrderFront(nil)
        } else {
          panel.orderFrontRegardless()
        }
        return panel
      }
    }
  }

  func close() {
    cursorDisplayLink?.invalidate()
    cursorDisplayLink = nil
    warningHost = nil
    panels.forEach {
      $0.orderOut(nil)
      $0.close()
    }
    panels = []
    shown = nil
    shownReminder = nil
  }
  private func configure(_ panel: NSPanel) {
    panel.isReleasedWhenClosed = false
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
  }
  private func positionWarning() {
    guard let panel = panels.first else { return }
    let cursor = cursorLocation()
    let screen = NSScreen.screens.first(where: { $0.frame.contains(cursor) }) ?? NSScreen.main
    guard let safe = screen?.visibleFrame.insetBy(dx: 12, dy: 12) else { return }
    var origin = NSPoint(x: cursor.x + 22, y: cursor.y - panel.frame.height - 22)
    origin.x = min(max(origin.x, safe.minX), safe.maxX - panel.frame.width)
    origin.y = min(max(origin.y, safe.minY), safe.maxY - panel.frame.height)
    if panel.frame.origin != origin {
      panel.setFrameOrigin(origin)
    }
  }
  private func centered(size: NSSize, in rect: NSRect) -> NSRect {
    NSRect(
      x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width,
      height: size.height)
  }
  private func safeFrame(for screen: NSScreen) -> NSRect {
    screen.visibleFrame.insetBy(dx: 8, dy: 8)
  }
}

@MainActor private final class CursorFrameTarget: NSObject {
  let update: () -> Void
  init(update: @escaping () -> Void) { self.update = update }
  @objc func frame() { update() }
}

private final class EscapePanel: NSPanel {
  var onEscape: (() -> Void)?
  override var canBecomeKey: Bool { true }
  override func cancelOperation(_ sender: Any?) { onEscape?() }
}
