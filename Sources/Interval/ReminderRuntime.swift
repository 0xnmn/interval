import AppKit
import CoreGraphics
import IntervalCore
import QuartzCore
import SwiftUI

enum UserIdleMonitor {
  static var keyboardIdleSeconds: TimeInterval {
    [.keyDown, .keyUp].map { (type: CGEventType) in
      CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: type)
    }.min() ?? 0
  }

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
  private let wallpaperForScreen: (@MainActor (NSScreen) -> NSImage?)?
  private var wallpaperTasks: [Task<Void, Never>] = []
  private let cueCallback: ((ReminderSound) -> Void)?
  private var cueSound: NSSound?
  private var lastCueOccurrence: CueOccurrence?

  init(
    cursorLocation: @escaping () -> NSPoint = { NSEvent.mouseLocation },
    playCue: ((ReminderSound) -> Void)? = nil,
    wallpaperForScreen: (@MainActor (NSScreen) -> NSImage?)? = nil
  ) {
    self.cursorLocation = cursorLocation
    self.wallpaperForScreen = wallpaperForScreen
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
        warningHost?.rootView = ReminderWarningView(
          reminder: reminder, overlay: overlay, audioInputActivity: store.audioInputActivity)
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
        contentRect: NSRect(origin: .zero, size: ReminderWarningView.size),
        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
      configure(panel)
      panel.hasShadow = false
      panel.level = .floating
      let host = NSHostingView(
        rootView: ReminderWarningView(
          reminder: reminder, overlay: overlay, audioInputActivity: store.audioInputActivity))
      warningHost = host
      panel.contentView = host
      panel.ignoresMouseEvents = true
      panels = [panel]
      positionWarning()
      IntervalMotion.reveal(panel)
      panel.orderFrontRegardless()
      let target = CursorFrameTarget { [weak self] in self?.positionWarning() }
      let link = panel.displayLink(target: target, selector: #selector(CursorFrameTarget.frame))
      link.add(to: .main, forMode: .common)
      cursorDisplayLink = link
    case .reminder(_, let shownAt):
      playCueOnce(reminder.sound, reminderID: reminder.id, shownAt: shownAt)
      let isPreview = store.previewReminderID == reminder.id
      if reminder.presentation == .overlay {
        guard
          let screen = NSScreen.screens.first(where: { $0.frame.contains(cursorLocation()) })
            ?? NSScreen.main
        else { return }
        let host = NSHostingView(
          rootView: ReminderOverlayView(reminder: reminder, shownAt: shownAt))
        let size = host.fittingSize
        let panel = NSPanel(
          contentRect: NSRect(
            x: screen.visibleFrame.midX - size.width / 2,
            y: screen.visibleFrame.midY - size.height / 2, width: size.width, height: size.height),
          styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        configure(panel)
        panel.level = .screenSaver
        panel.collectionBehavior = [
          .canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .ignoresCycle,
        ]
        panel.ignoresMouseEvents = true
        panel.contentView = host
        panels = [panel]
        IntervalMotion.reveal(panel)
        panel.orderFrontRegardless()
        return
      }
      // Foreground apps cannot join another app's native fullscreen Space.
      // Act as an overlay utility only for the takeover, then restore the Dock presence.
      let policy = NSApp.activationPolicy()
      if policy == .regular, NSApp.setActivationPolicy(.accessory) {
        previousActivationPolicy = policy
      }
      let cursor = cursorLocation()
      let cursorScreen =
        NSScreen.screens.first(where: { $0.frame.contains(cursor) }) ?? NSScreen.main
      // Injected images stay synchronous; production captures only the desktop backdrop asynchronously.
      let backgrounds = NSScreen.screens.map { ($0, wallpaperForScreen?($0)) }
      panels = backgrounds.map { screen, wallpaper in
        let rect = screen.frame
        let panel = EscapePanel(
          contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
          defer: false)
        configure(panel)
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        // isFloatingPanel resets the level; apply the overlay level afterward.
        panel.level = .screenSaver
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [
          .canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .stationary,
          .ignoresCycle,
        ]
        // Set after the level: normal window positioning may otherwise constrain the
        // frame to the desktop work area, excluding the menu bar and Dock.
        panel.setFrame(rect, display: false)
        let host = NSHostingView(
          rootView: ReminderTakeoverView(
            reminder: reminder,
            shownAt: shownAt,
            skip: { store.dismissReminder(reminder.id) },
            extend: { store.snoozeReminder(reminder.id, seconds: $0) },
            wallpaper: wallpaper, animatesEntrance: !preservesCue, isPreview: isPreview))
        host.safeAreaRegions = []
        panel.contentView = host
        if wallpaperForScreen == nil {
          wallpaperTasks.append(
            Task { [weak host] in
              let image = await Wallpaper.image(for: screen)
              guard !Task.isCancelled, let host else { return }
              host.rootView.wallpaper = image
            })
        }
        var shortcut = ReminderSkipShortcut()
        panel.onEscape = {
          if let event = NSApp.currentEvent, event.type == .keyDown, event.isARepeat {
            return
          }
          if isPreview {
            store.dismissReminder(reminder.id)
          } else if shortcut.press(at: Date(), shownAt: shownAt) {
            store.dismissReminder(reminder.id)
          }
        }
        panel.sharingType = .readOnly
        // A display configuration change rebuilds the same occurrence, not a new entrance.
        if !preservesCue { IntervalMotion.reveal(panel) }
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
    wallpaperTasks.forEach { $0.cancel() }
    wallpaperTasks.removeAll()
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

struct ReminderSkipShortcut {
  private var lastPress: Date?

  mutating func press(at date: Date, shownAt: Date) -> Bool {
    guard date.timeIntervalSince(shownAt) >= 5 else {
      lastPress = nil
      return false
    }
    if let previous = lastPress, (0...1).contains(date.timeIntervalSince(previous)) {
      lastPress = nil
      return true
    }
    lastPress = date
    return false
  }
}
