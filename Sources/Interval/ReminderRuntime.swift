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
  private weak var shownStore: AppStore?
  private var warningHost: NSHostingView<ReminderWarningView>?
  private var cursorDisplayLink: CADisplayLink?
  private var previousActivationPolicy: NSApplication.ActivationPolicy?
  private let cursorLocation: () -> NSPoint
  private let cueCallback: ((ReminderSound) -> Void)?
  private var cueSound: NSSound?
  private var lastCueOccurrence: CueOccurrence?

  init(
    cursorLocation: @escaping () -> NSPoint = { NSEvent.mouseLocation },
    playCue: ((ReminderSound) -> Void)? = nil
  ) {
    self.cursorLocation = cursorLocation
    self.cueCallback = playCue
    super.init()
    NotificationCenter.default.addObserver(
      self, selector: #selector(screensChanged),
      name: NSApplication.didChangeScreenParametersNotification, object: nil)
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
    let preservesCue: Bool
    if case .reminder(let id, let shownAt) = overlay {
      preservesCue = lastCueOccurrence == CueOccurrence(reminderID: id, shownAt: shownAt)
    } else {
      preservesCue = false
    }
    close(preservingCue: preservesCue)
    shown = overlay
    shownReminder = reminder
    shownStore = store
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
    case .reminder(_, let shownAt):
      playCueOnce(reminder.sound, reminderID: reminder.id, shownAt: shownAt)
      if reminder.presentation == .fullscreen {
        // Foreground apps cannot join another app's native fullscreen Space.
        // Act as an overlay utility only for the takeover, then restore the Dock presence.
        let policy = NSApp.activationPolicy()
        if policy == .regular, NSApp.setActivationPolicy(.accessory) {
          previousActivationPolicy = policy
        }
      }
      let cursor = cursorLocation()
      let cursorScreen =
        NSScreen.screens.first(where: { $0.frame.contains(cursor) }) ?? NSScreen.main
      let screens =
        reminder.presentation == .fullscreen ? NSScreen.screens : [cursorScreen].compactMap { $0 }
      panels = screens.map { screen in
        let rect =
          reminder.presentation == .fullscreen
          ? screen.frame
          : Self.floatingFrame(
            size: Self.floatingSize(for: reminder), in: screen.visibleFrame,
            position: reminder.position)
        let panel = EscapePanel(
          contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
          defer: false)
        configure(panel)
        let fullscreen = reminder.presentation == .fullscreen
        panel.hasShadow = !fullscreen
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        // isFloatingPanel resets the level; apply the overlay level afterward.
        panel.level = fullscreen ? .screenSaver : .floating
        panel.isMovable = !fullscreen
        panel.isMovableByWindowBackground = !fullscreen
        panel.animationBehavior = .none
        panel.collectionBehavior = [
          .canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .stationary,
          .ignoresCycle,
        ]
        // Set after the level: normal window positioning may otherwise constrain the
        // frame to the desktop work area, excluding the menu bar and Dock.
        panel.setFrame(rect, display: false)
        panel.contentView = NSHostingView(
          rootView: ReminderTakeoverView(
            reminder: reminder,
            shownAt: shownAt,
            skip: { store.dismissReminder(reminder.id) },
            extend: { store.snoozeReminder(reminder.id, seconds: $0) }))
        panel.onEscape = { store.dismissReminder(reminder.id) }
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

  func close(preservingCue: Bool = false) {
    shownStore = nil
    if !preservingCue {
      cueSound?.stop()
      cueSound = nil
    }
    cursorDisplayLink?.invalidate()
    cursorDisplayLink = nil
    warningHost = nil
    panels.forEach {
      $0.orderOut(nil)
      $0.close()
    }
    panels = []
    if let policy = previousActivationPolicy {
      previousActivationPolicy = nil
      NSApp.setActivationPolicy(policy)
    }
    shown = nil
    shownReminder = nil
  }
  @objc private func screensChanged() {
    guard let overlay = shown, let reminder = shownReminder,
      let store = shownStore
    else { return }
    // Rebuild without toggling app policy (which can itself change desktop geometry).
    let policy = previousActivationPolicy
    previousActivationPolicy = nil
    shown = nil
    update(overlay, reminder: reminder, store: store)
    previousActivationPolicy = policy
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

  static func floatingSize(for reminder: Reminder) -> NSSize {
    NSSize(width: 480, height: max(320, reminder.clamped().emojiSize + 240))
  }

  static func floatingFrame(
    size: NSSize, in visibleFrame: NSRect, position: ReminderPosition, margin: CGFloat = 24
  ) -> NSRect {
    let x: CGFloat
    let y: CGFloat
    switch position {
    case .topLeft:
      x = visibleFrame.minX + margin
      y = visibleFrame.maxY - size.height - margin
    case .topRight:
      x = visibleFrame.maxX - size.width - margin
      y = visibleFrame.maxY - size.height - margin
    case .bottomLeft:
      x = visibleFrame.minX + margin
      y = visibleFrame.minY + margin
    case .bottomRight:
      x = visibleFrame.maxX - size.width - margin
      y = visibleFrame.minY + margin
    case .center:
      x = visibleFrame.midX - size.width / 2
      y = visibleFrame.midY - size.height / 2
    }
    return NSRect(origin: NSPoint(x: x, y: y), size: size)
  }

  private func playCueOnce(_ sound: ReminderSound, reminderID: UUID, shownAt: Date) {
    let occurrence = CueOccurrence(reminderID: reminderID, shownAt: shownAt)
    guard occurrence != lastCueOccurrence else { return }
    lastCueOccurrence = occurrence
    guard sound != .none else { return }
    if let cueCallback {
      cueCallback(sound)
      return
    }
    cueSound?.stop()
    let systemSound = NSSound(named: NSSound.Name(sound.title))
    cueSound = systemSound
    systemSound?.play()
  }
}

private struct CueOccurrence: Equatable {
  let reminderID: UUID
  let shownAt: Date
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
