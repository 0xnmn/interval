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
    } else if expanded {
      reposition(animated: false)
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
    panel.sharingType = .readOnly
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
    // The panel owns its animated size; SwiftUI's expanded intrinsic size must not
    // impose a minimum window size while the panel is collapsing.
    host.sizingOptions = []
    // This surface deliberately occupies the camera band. Its root reserves the
    // cutout itself; AppKit's automatic safe area would push the compact content out.
    host.safeAreaRegions = []
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
    let frame = geometry.frame(
      expanded: expanded, in: screen.frame,
      reflection: store?.completionSessionID != nil)
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
  static let expandedSize = NSSize(width: 420, height: 360)
  static let reflectionHeight: CGFloat = 480

  let hasHardwareNotch: Bool
  let cutoutWidth: CGFloat
  let topInset: CGFloat

  var compactSize: NSSize {
    hasHardwareNotch
      ? NSSize(width: max(190, cutoutWidth + 176), height: max(30, topInset))
      : NSSize(width: 150, height: 32)
  }

  func frame(expanded: Bool, in screenFrame: NSRect, reflection: Bool = false) -> NSRect {
    let size =
      expanded
      ? NSSize(
        width: Self.expandedSize.width,
        height: (reflection ? Self.reflectionHeight : Self.expandedSize.height) + topInset)
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
  @State var page = 0

  private var accent: Color {
    (store.timer.kind == .focus ? store.data.settings.focusColor : store.data.settings.breakColor)
      .color
  }

  var body: some View {
    if expanded {
      VStack(spacing: 0) {
        Color.black.frame(height: geometry.topInset)
        VStack(spacing: 18) {
          HStack {
            Image(systemName: store.timer.kind == .focus ? "timer" : "cup.and.saucer")
              .foregroundStyle(accent)
            Text(
              store.completionSessionID != nil
                ? "Reflect"
                : store.breakEnded
                  ? "Break ended" : store.timer.kind == .focus ? "Focus" : "Taking a break"
            )
            .font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
            Spacer()
            ForEach(store.completionSessionID == nil ? 0..<3 : 0..<0) { index in
              Button {
                page = index
              } label: {
                Image(systemName: ["timer", "checklist", "bell"][index])
                  .frame(width: 26, height: 26)
                  .foregroundStyle(page == index ? .white : .gray)
                  .background(
                    page == index ? Color.white.opacity(0.12) : .clear,
                    in: RoundedRectangle(cornerRadius: 7))
              }.buttonStyle(.plain).help(["Timer", "To-dos", "Reminders"][index])
                .accessibilityLabel(["Timer", "To-dos", "Reminders"][index])
            }
            Button(action: collapse) {
              Image(systemName: "chevron.up").frame(width: 26, height: 26)
            }.buttonStyle(.plain).foregroundStyle(.secondary).help("Collapse")
          }
          if let id = store.completionSessionID {
            ScrollView { ReflectionView(store: store, sessionID: id) }
          } else if page == 1 {
            ScrollView { TodoList(store: store) }
          } else if page == 2 {
            ScrollView { UpcomingReminders(store: store) }
          } else {
            FocusControls(store: store, compact: true, showsDial: false)
          }
        }.padding(22)
          .frame(
            width: NotchGeometry.expandedSize.width,
            height: store.completionSessionID != nil
              ? NotchGeometry.reflectionHeight : NotchGeometry.expandedSize.height)
      }
      .background(.black)
      .environment(\.colorScheme, .dark)
      .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 24, bottomTrailingRadius: 24))
    } else {
      compact
    }
  }

  private var compact: some View {
    HStack(spacing: 0) {
      if geometry.hasHardwareNotch {
        Image(systemName: store.timer.kind == .focus ? "timer" : "cup.and.saucer")
          .font(.system(size: 15, weight: .medium))
          .foregroundStyle(accent).frame(width: 88)
        Color.clear.frame(width: geometry.cutoutWidth)
        Text(store.completionSessionID == nil ? store.timerText : "Reflect")
          .font(.system(size: 13, weight: .medium, design: .rounded)).monospacedDigit()
          .foregroundStyle(.white.opacity(0.9)).frame(width: 88)
      } else {
        Text(store.completionSessionID == nil ? store.timerText : "Reflect")
          .font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit()
          .padding(.horizontal, 18).frame(maxWidth: .infinity, maxHeight: .infinity)
          .foregroundStyle(.white)
      }
    }
    .frame(width: geometry.compactSize.width, height: geometry.compactSize.height)
    .background(
      Color.black,
      in: UnevenRoundedRectangle(bottomLeadingRadius: 10, bottomTrailingRadius: 10)
    )
    .contentShape(Rectangle())
    .accessibilityLabel(
      "\(store.breakEnded ? "Break ended" : store.timer.kind.title), \(spokenDuration(store.displayedTime)) \(store.breakEnded ? "overtime" : "remaining"). Hover to expand."
    )
  }
}
