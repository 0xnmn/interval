import AppKit
import SwiftUI

/// Owns the small, out-of-app completion prompt. `close()` only hides the current
/// prompt; call `update(store:)` again when interruptions no longer suppress it.
@MainActor final class SessionCompletionController: NSObject {
  enum Presentation: Equatable {
    case toast
    case reflection
  }

  static let toastSize = NSSize(width: 360, height: 132)
  static let reflectionSize = NSSize(width: 400, height: 400)

  private var panel: SessionCompletionPanel?
  private var sessionID: UUID?
  private var presentation: Presentation = .toast
  private var shownSessionIDs: Set<UUID> = []
  private var temporarilyHiddenSessionID: UUID?
  private weak var store: AppStore?
  private var screenID: NSNumber?

  override init() {
    super.init()
    NotificationCenter.default.addObserver(
      self, selector: #selector(screenGeometryChanged),
      name: NSApplication.didChangeScreenParametersNotification, object: nil)
  }

  /// Reconciles the panel with the store. This method never activates Interval or
  /// makes the toast key, so it is safe to call from the application's ticker.
  func update(store: AppStore) {
    guard store.data.settings.completionPopupEnabled, let id = store.completionSessionID else {
      dismissCurrent()
      return
    }

    if sessionID == id, panel != nil { return }

    let resumingTemporaryHide = temporarilyHiddenSessionID == id
    guard resumingTemporaryHide || !shownSessionIDs.contains(id) else { return }
    dismissPanel()
    temporarilyHiddenSessionID = nil
    shownSessionIDs.insert(id)
    sessionID = id
    self.store = store
    screenID = nil
    presentation = .toast
    showToast()
  }

  /// Temporarily removes the prompt for an app-inactive or fullscreen interruption.
  /// Unlike Later/Escape, the same completion may be presented by the next update.
  func close() {
    guard panel != nil else { return }
    temporarilyHiddenSessionID = sessionID
    dismissPanel()
  }

  static func frame(
    size: NSSize, in visibleFrame: NSRect, margin: CGFloat = 24
  ) -> NSRect {
    NSRect(
      x: visibleFrame.maxX - size.width - margin,
      y: visibleFrame.maxY - size.height - margin,
      width: size.width, height: size.height)
  }

  private func showToast() {
    let panel = makePanel(size: Self.toastSize)
    panel.contentView = NSHostingView(
      rootView: SessionCompletionToast(
        later: { [weak self] in self?.dismissPermanently() },
        reflect: { [weak self] in self?.showReflection() }))
    panel.onEscape = { [weak self] in self?.dismissPermanently() }
    self.panel = panel
    position(panel)
    panel.orderFrontRegardless()
  }

  private func showReflection() {
    guard let panel, let store, let sessionID else { return }
    presentation = .reflection
    panel.contentView = NSHostingView(
      rootView: ReflectionView(store: store, sessionID: sessionID)
        .padding(24)
        .background(GlassBackground())
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous)))
    panel.setFrame(Self.frame(size: Self.reflectionSize, in: targetVisibleFrame()), display: true)
    // The explicit click on Reflect opts into keyboard interaction without activating
    // the application or opening its main window.
    panel.makeKeyAndOrderFront(nil)
  }

  private func makePanel(size: NSSize) -> SessionCompletionPanel {
    let panel = SessionCompletionPanel(
      contentRect: NSRect(origin: .zero, size: size),
      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.isReleasedWhenClosed = false
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.hidesOnDeactivate = false
    panel.isFloatingPanel = true
    panel.level = .floating
    panel.animationBehavior = .utilityWindow
    panel.collectionBehavior = [
      .canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle,
    ]
    panel.sharingType = .none
    return panel
  }

  private func dismissPermanently() {
    temporarilyHiddenSessionID = nil
    dismissPanel()
  }

  private func dismissCurrent() {
    temporarilyHiddenSessionID = nil
    sessionID = nil
    store = nil
    presentation = .toast
    dismissPanel()
  }

  private func dismissPanel() {
    panel?.orderOut(nil)
    panel?.close()
    panel = nil
  }

  private func position(_ panel: NSPanel) {
    let size = presentation == .toast ? Self.toastSize : Self.reflectionSize
    panel.setFrame(Self.frame(size: size, in: targetVisibleFrame()), display: true)
  }

  private func targetVisibleFrame() -> NSRect {
    let key = NSDeviceDescriptionKey("NSScreenNumber")
    if let screenID,
      let screen = NSScreen.screens.first(where: {
        $0.deviceDescription[key] as? NSNumber == screenID
      })
    {
      return screen.visibleFrame
    }
    let cursor = NSEvent.mouseLocation
    let screen = NSScreen.screens.first { $0.frame.contains(cursor) } ?? NSScreen.main
    screenID = screen?.deviceDescription[key] as? NSNumber
    return screen?.visibleFrame
      ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
  }

  @objc private func screenGeometryChanged() {
    if let panel { position(panel) }
  }
}

private final class SessionCompletionPanel: NSPanel {
  var onEscape: (() -> Void)?
  override var canBecomeKey: Bool { true }
  override func cancelOperation(_ sender: Any?) { onEscape?() }
}

struct SessionCompletionToast: View {
  let later: () -> Void
  let reflect: () -> Void

  var body: some View {
    HStack(alignment: .top, spacing: 14) {
      Text("🎉").font(.system(size: 30)).padding(.top, 2).accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 3) {
        Text("How did that session feel?").font(.system(size: 16, weight: .bold))
        Text("Take a moment to capture how it went.")
          .font(IntervalTheme.body).foregroundStyle(.secondary)
        HStack(spacing: 8) {
          Spacer()
          Button("Later", action: later).buttonStyle(CompletionPillButtonStyle(prominent: false))
          Button("Reflect", action: reflect).buttonStyle(CompletionPillButtonStyle(prominent: true))
        }.padding(.top, 8)
      }
    }
    .padding(18)
    .frame(
      width: SessionCompletionController.toastSize.width,
      height: SessionCompletionController.toastSize.height
    )
    .background(GlassBackground())
    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(IntervalTheme.border)
    }
  }
}

private struct CompletionPillButtonStyle: ButtonStyle {
  let prominent: Bool

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.callout.weight(.semibold))
      .padding(.horizontal, 15).padding(.vertical, 7)
      .background(
        prominent
          ? Color.accentColor.opacity(configuration.isPressed ? 0.42 : 0.27)
          : Color.primary.opacity(configuration.isPressed ? 0.14 : 0.07),
        in: Capsule()
      )
      .overlay { Capsule().strokeBorder(IntervalTheme.border) }
      .contentShape(Capsule())
  }
}
