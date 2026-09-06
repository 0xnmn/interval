import AppKit
import SwiftUI

/// Owns the optional, top-of-screen timer surface. The application lifecycle is responsible for
/// calling `close()` while Interval is suppressed (for example, at the lock screen or underneath a
/// fullscreen reminder) and for resuming calls to `update(store:)` when it may be shown again.
@MainActor
final class NotchController: NSObject {
  private weak var store: AppStore?
  private var panel: NotchPanel?
  private var trackingView: NotchTrackingView?
  private var host: NSHostingView<NotchRootView>?
  private var expanded = false
  private var collapseTask: Task<Void, Never>?

  override init() {
    super.init()
    NotificationCenter.default.addObserver(
      self, selector: #selector(screenParametersChanged),
      name: NSApplication.didChangeScreenParametersNotification, object: nil)
  }

  deinit { collapseTask?.cancel() }

  func update(store: AppStore) {
    guard store.data.settings.notchEnabled else {
      close()
      return
    }

    self.store = store
    if panel == nil {
      makePanel(store: store)
      reposition(animated: false)
      panel?.orderFrontRegardless()
    }
  }

  func close() {
    collapseTask?.cancel()
    collapseTask = nil
    panel?.orderOut(nil)
    panel?.close()
    panel = nil
    trackingView = nil
    host = nil
    store = nil
    expanded = false
  }

  private func makePanel(store: AppStore) {
    let panel = NotchPanel(
      contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
      defer: false)
    panel.isReleasedWhenClosed = false
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.sharingType = .none
    panel.hasShadow = true
    panel.hidesOnDeactivate = false
    panel.isFloatingPanel = true
    panel.level = .statusBar
    panel.animationBehavior = .none
    panel.collectionBehavior = [
      .canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle,
    ]
    panel.onEscape = { [weak self] in self?.collapse() }

    let trackingView = NotchTrackingView()
    trackingView.onEnter = { [weak self] in self?.expand() }
    trackingView.onExit = { [weak self] in self?.scheduleCollapse() }
    let host = NSHostingView(
      rootView: NotchRootView(store: store, expanded: false, geometry: geometry(), collapse: {}))
    host.translatesAutoresizingMaskIntoConstraints = false
    trackingView.addSubview(host)
    NSLayoutConstraint.activate([
      host.leadingAnchor.constraint(equalTo: trackingView.leadingAnchor),
      host.trailingAnchor.constraint(equalTo: trackingView.trailingAnchor),
      host.topAnchor.constraint(equalTo: trackingView.topAnchor),
      host.bottomAnchor.constraint(equalTo: trackingView.bottomAnchor),
    ])
    panel.contentView = trackingView
    self.panel = panel
    self.trackingView = trackingView
    self.host = host
    refreshRoot()
  }

  private func expand() {
    collapseTask?.cancel()
    collapseTask = nil
    guard !expanded else { return }
    expanded = true
    refreshRoot()
    reposition(animated: true)
  }

  private func scheduleCollapse() {
    collapseTask?.cancel()
    collapseTask = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(450))
      guard !Task.isCancelled else { return }
      self?.collapseUnlessEditing()
    }
  }

  private func collapseUnlessEditing() {
    guard let panel else { return }
    // A field editor is an NSTextView even when the SwiftUI control is a TextField.
    if panel.firstResponder is NSTextView { return }
    collapse()
  }

  private func collapse() {
    collapseTask?.cancel()
    collapseTask = nil
    guard expanded else { return }
    expanded = false
    panel?.resignKey()
    refreshRoot()
    reposition(animated: true)
  }

  private func refreshRoot() {
    guard let store else { return }
    host?.rootView = NotchRootView(
      store: store, expanded: expanded, geometry: geometry(),
      collapse: { [weak self] in self?.collapse() })
  }

  private func reposition(animated: Bool) {
    guard let panel, let screen = targetScreen() else { return }
    let geometry = Self.geometry(for: screen)
    let frame = geometry.frame(expanded: expanded, in: screen.frame)
    if panel.frame == frame { return }
    if animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
      NSAnimationContext.runAnimationGroup { context in
        context.duration = 0.18
        context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        panel.animator().setFrame(frame, display: true)
      }
    } else {
      panel.setFrame(frame, display: true)
    }
  }

  private func geometry() -> NotchGeometry {
    targetScreen().map(Self.geometry(for:)) ?? .fallback
  }

  private func targetScreen() -> NSScreen? {
    NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.screens.first
  }

  @objc private func screenParametersChanged() {
    guard panel != nil else { return }
    refreshRoot()
    reposition(animated: false)
  }

  static func geometry(for screen: NSScreen) -> NotchGeometry {
    guard screen.safeAreaInsets.top > 0,
      let left = screen.auxiliaryTopLeftArea,
      let right = screen.auxiliaryTopRightArea,
      right.minX > left.maxX
    else { return .fallback }
    return NotchGeometry(
      hasHardwareNotch: true, cutoutWidth: right.minX - left.maxX,
      topInset: screen.safeAreaInsets.top)
  }
}

struct NotchGeometry: Equatable {
  static let fallback = NotchGeometry(hasHardwareNotch: false, cutoutWidth: 0, topInset: 0)
  static let expandedSize = NSSize(width: 600, height: 480)

  let hasHardwareNotch: Bool
  let cutoutWidth: CGFloat
  let topInset: CGFloat

  var compactSize: NSSize {
    hasHardwareNotch
      ? NSSize(width: max(190, cutoutWidth + 176), height: max(30, topInset))
      : NSSize(width: 150, height: 32)
  }

  func frame(expanded: Bool, in screenFrame: NSRect) -> NSRect {
    let size =
      expanded
      ? NSSize(width: Self.expandedSize.width, height: Self.expandedSize.height + topInset)
      : compactSize
    return NSRect(
      x: screenFrame.midX - size.width / 2, y: screenFrame.maxY - size.height,
      width: size.width, height: size.height)
  }
}

private final class NotchPanel: NSPanel {
  var onEscape: (() -> Void)?
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
  override func cancelOperation(_ sender: Any?) { onEscape?() }
  override func sendEvent(_ event: NSEvent) {
    // Stay nonactivating while merely visible or hovered, but allow controls and field editors to
    // receive keyboard input after an intentional click.
    if event.type == .leftMouseDown { makeKey() }
    super.sendEvent(event)
  }
}

private final class NotchTrackingView: NSView {
  var onEnter: (() -> Void)?
  var onExit: (() -> Void)?
  private var tracking: NSTrackingArea?

  override func updateTrackingAreas() {
    if let tracking { removeTrackingArea(tracking) }
    let tracking = NSTrackingArea(
      rect: bounds, options: [.activeAlways, .mouseEnteredAndExited], owner: self, userInfo: nil)
    addTrackingArea(tracking)
    self.tracking = tracking
    super.updateTrackingAreas()
  }

  override func mouseEntered(with event: NSEvent) { onEnter?() }
  override func mouseExited(with event: NSEvent) { onExit?() }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

struct NotchRootView: View {
  @Bindable var store: AppStore
  let expanded: Bool
  let geometry: NotchGeometry
  let collapse: () -> Void

  var body: some View {
    if expanded {
      VStack(spacing: 0) {
        Color.black.frame(height: geometry.topInset)
        ZStack(alignment: .topTrailing) {
          MenuBarView(store: store, showsAppActions: false)
          Button(action: collapse) {
            Image(systemName: "chevron.up")
              .font(.caption.weight(.semibold)).frame(width: 28, height: 28)
          }
          .buttonStyle(.plain).background(.thinMaterial, in: Circle()).padding(8)
          .help("Collapse")
        }
      }.clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 22, bottomTrailingRadius: 22))
    } else {
      compact
    }
  }

  private var compact: some View {
    HStack(spacing: 0) {
      if geometry.hasHardwareNotch {
        Image(systemName: store.timer.kind == .focus ? "timer" : "cup.and.saucer")
          .foregroundStyle(.white.opacity(0.9)).frame(width: 88)
        Color.clear.frame(width: geometry.cutoutWidth)
        Text(store.completionSessionID == nil ? store.timerText : "Reflect")
          .font(.system(size: 11, weight: .medium, design: .rounded)).monospacedDigit()
          .foregroundStyle(.white.opacity(0.9)).frame(width: 88)
      } else {
        Text(store.completionSessionID == nil ? store.timerText : "Reflect")
          .font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit()
          .padding(.horizontal, 18).frame(maxWidth: .infinity, maxHeight: .infinity)
          .background(GlassBackground())
      }
    }
    .frame(width: geometry.compactSize.width, height: geometry.compactSize.height)
    .background(
      geometry.hasHardwareNotch ? Color.black : Color.clear,
      in: UnevenRoundedRectangle(bottomLeadingRadius: 10, bottomTrailingRadius: 10)
    )
    .contentShape(Rectangle())
    .accessibilityLabel(
      "\(store.breakEnded ? "Break ended" : store.timer.kind.title), \(spokenDuration(store.displayedTime)) \(store.breakEnded ? "overtime" : "remaining"). Hover to expand."
    )
  }
}
