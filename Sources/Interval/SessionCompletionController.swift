import AppKit
import IntervalCore
import SwiftUI

/// Owns the small, out-of-app completion prompt. `close()` only hides the current
/// prompt; call `update(store:)` again when interruptions no longer suppress it.
@MainActor final class SessionCompletionController: NSObject {
  enum Presentation: Equatable {
    case almostTime
    case toast
    case reflection
  }

  struct AlmostTimeState: Equatable {
    private(set) var timerID: UUID?
    private(set) var suppressed = false

    mutating func shouldPresent(timer: TimerState?, remaining: TimeInterval) -> Bool {
      guard let timer, timer.kind == .focus, timer.status == .running else {
        timerID = nil
        suppressed = false
        return false
      }
      if timerID != timer.id {
        timerID = timer.id
        suppressed = false
      }
      guard remaining > 0, remaining <= 60 else {
        suppressed = false
        return false
      }
      return !suppressed
    }

    mutating func suppress() { suppressed = true }
  }

  static let toastSize = NSSize(width: 360, height: 132)
  static let almostTimeSize = NSSize(width: 420, height: 132)
  static let reflectionSize = NSSize(width: 400, height: 400)

  private var panel: SessionCompletionPanel?
  private var sessionID: UUID?
  private var presentation: Presentation = .toast
  private var shownSessionIDs: Set<UUID> = []
  private var temporarilyHiddenSessionID: UUID?
  private weak var store: AppStore?
  private var screenID: NSNumber?
  private var almostTimeState = AlmostTimeState()

  override init() {
    super.init()
    NotificationCenter.default.addObserver(
      self, selector: #selector(screenGeometryChanged),
      name: NSApplication.didChangeScreenParametersNotification, object: nil)
  }

  /// Reconciles the panel with the store. This method never activates Interval or
  /// makes the toast key, so it is safe to call from the application's ticker.
  func update(store: AppStore) {
    guard store.data.settings.completionPopupEnabled else {
      _ = almostTimeState.shouldPresent(timer: nil, remaining: 0)
      dismissCurrent()
      return
    }

    if let id = store.completionSessionID {
      updateCompletion(store: store, id: id)
      return
    }

    let timer = store.data.activeTimer
    guard almostTimeState.shouldPresent(timer: timer, remaining: store.remaining) else {
      dismissCurrent()
      return
    }
    guard let timer else { return }
    if presentation == .almostTime, sessionID == timer.id, panel != nil { return }

    dismissPanel()
    temporarilyHiddenSessionID = nil
    sessionID = timer.id
    self.store = store
    screenID = nil
    presentation = .almostTime
    showAlmostTime()
  }

  private func updateCompletion(store: AppStore, id: UUID) {
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
    IntervalMotion.reveal(panel)
    panel.orderFrontRegardless()
  }

  private func showAlmostTime() {
    guard let store else { return }
    let panel = makePanel(size: Self.almostTimeSize)
    panel.contentView = NSHostingView(
      rootView: AlmostTimeToast(
        store: store,
        startBreak: { [weak self] in
          self?.store?.startBreakNow()
          self?.dismissCurrent()
        },
        extend: { [weak self] seconds in
          self?.store?.adjustCurrentTime(by: seconds)
          self?.dismissCurrent()
        }))
    panel.onEscape = { [weak self] in
      self?.almostTimeState.suppress()
      self?.dismissPanel()
    }
    self.panel = panel
    position(panel)
    IntervalMotion.reveal(panel)
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
    IntervalMotion.reveal(panel)
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
    panel.animationBehavior = .none
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
    let size =
      switch presentation {
      case .almostTime: Self.almostTimeSize
      case .toast: Self.toastSize
      case .reflection: Self.reflectionSize
      }
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

struct AlmostTimeToast: View {
  let store: AppStore
  let startBreak: () -> Void
  let extend: (TimeInterval) -> Void

  private var suggestedBreakText: String {
    let longBreak =
      (store.data.completedFocusCount + 1) % max(1, store.data.settings.longBreakEvery) == 0
    let minutes =
      longBreak
      ? store.data.settings.longBreakMinutes : store.data.settings.shortBreakMinutes
    return "Almost time. \(longBreak ? "Long break" : "Short break") · \(minutes) min"
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(spacing: 12) {
        Image(systemName: "timer")
          .font(.system(size: 28, weight: .medium))
          .foregroundStyle(store.data.settings.focusColor.color)
          .frame(width: 44, height: 44)
          .background(
            store.data.settings.focusColor.color.opacity(0.12),
            in: RoundedRectangle(cornerRadius: 12))
        VStack(alignment: .leading, spacing: 3) {
          Text(durationString(store.remaining))
            .font(.title2.weight(.semibold)).monospacedDigit()
          Text(suggestedBreakText).font(IntervalTheme.body).foregroundStyle(.secondary)
        }
        Spacer()
      }
      HStack(spacing: 8) {
        Button("Start break now", action: startBreak)
          .buttonStyle(CompletionPillButtonStyle(prominent: true))
        ForEach([1, 5, 15], id: \.self) { minutes in
          Button("+\(minutes)m") { extend(TimeInterval(minutes * 60)) }
            .buttonStyle(CompletionPillButtonStyle(prominent: false))
            .disabled(store.timer.duration + TimeInterval(minutes * 60) > 3_600)
        }
      }
    }
    .padding(18)
    .frame(
      width: SessionCompletionController.almostTimeSize.width,
      height: SessionCompletionController.almostTimeSize.height
    )
    .background(GlassBackground())
    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(IntervalTheme.border)
    }
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
  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var hovering = false

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 13, weight: .medium))
      .padding(.horizontal, 15).padding(.vertical, 7)
      .background(
        prominent
          ? Color.accentColor.opacity(configuration.isPressed ? 0.42 : hovering ? 0.34 : 0.27)
          : Color.primary.opacity(configuration.isPressed ? 0.18 : hovering ? 0.12 : 0.07),
        in: Capsule()
      )
      .overlay { Capsule().strokeBorder(IntervalTheme.border) }
      .contentShape(Capsule())
      .opacity(isEnabled ? 1 : 0.4)
      .animation(reduceMotion ? nil : IntervalMotion.selection, value: hovering)
      .animation(reduceMotion ? nil : IntervalMotion.selection, value: configuration.isPressed)
      .onHover { hovering = $0 }
  }
}
