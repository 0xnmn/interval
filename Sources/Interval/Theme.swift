import AppKit
import IntervalCore
import SwiftUI

enum IntervalTheme {
  static let accent = Color.accentColor
  static let surface = Color(
    nsColor: NSColor(name: nil) { appearance in
      let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
      return NSColor(white: dark ? 0.12 : 0.97, alpha: 1)
    })
  static let border = Color.primary.opacity(0.07)
  static let body = Font.system(size: 14)
  static let heading = Font.system(size: 14, weight: .semibold)
  static let icon = Font.system(size: 16, weight: .medium)
}

enum IntervalMotion {
  static let selection = Animation.easeInOut(duration: 0.16)
  static let entrance = Animation.easeOut(duration: 0.28)

  // Only fade on entry. Dismissal stays immediate so an invisible overlay can never block work.
  @MainActor static func reveal(_ window: NSWindow, reduceMotion: Bool? = nil) {
    let reduced = reduceMotion ?? NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    guard !reduced else {
      window.alphaValue = 1
      return
    }
    window.alphaValue = 0
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.24
      window.animator().alphaValue = 1
    }
  }
}

/// One-shot, compositor-only motion. State survives countdown updates, and SwiftUI
/// cancels the delay if the surface closes before its entrance has begun.
private struct IntervalEntrance: ViewModifier {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.intervalMotionDisabled) private var motionDisabled
  @State private var revealed = false
  let delay: TimeInterval
  let enabled: Bool

  private var visible: Bool { revealed || reduceMotion || motionDisabled || !enabled }

  func body(content: Content) -> some View {
    content
      .opacity(visible ? 1 : 0)
      .offset(y: visible ? 0 : 6)
      .disabled(!visible)
      .allowsHitTesting(visible)
      .accessibilityHidden(!visible)
      .task(id: reduceMotion || motionDisabled) {
        guard !visible else {
          revealed = true
          return
        }
        do {
          try await Task.sleep(for: .seconds(delay))
          try Task.checkCancellation()
          withAnimation(IntervalMotion.entrance) { revealed = true }
        } catch { /* Closing a surface cancels its pending entrance. */  }
      }
  }
}

extension EnvironmentValues {
  // Also supports deterministic reduced-motion captures without changing macOS preferences.
  @Entry var intervalMotionDisabled = false
}

extension View {
  func intervalEntrance(delay: TimeInterval = 0, enabled: Bool = true) -> some View {
    modifier(IntervalEntrance(delay: delay, enabled: enabled))
  }
}

extension AppAppearance {
  var nativeAppearance: NSAppearance? {
    switch self {
    case .system: nil
    case .light: NSAppearance(named: .aqua)
    case .dark: NSAppearance(named: .darkAqua)
    }
  }

  @MainActor func apply() {
    // Nil removes the override so AppKit tracks macOS changes automatically.
    NSApplication.shared.appearance = nativeAppearance
  }
}

extension PhaseColor {
  var color: Color {
    switch self {
    case .green: .green
    case .blue: .blue
    case .teal: .teal
    case .orange: .orange
    case .red: .red
    case .pink: .pink
    case .purple: .purple
    }
  }
}

struct IntervalIconButton: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var hovering = false

  func makeBody(configuration: Configuration) -> some View {
    configuration.label.labelStyle(.iconOnly)
      .font(IntervalTheme.icon)
      .frame(width: 36, height: 36)
      .background(
        Color.primary.opacity(configuration.isPressed ? 0.18 : hovering ? 0.12 : 0.06),
        in: RoundedRectangle(cornerRadius: 9)
      )
      .contentShape(RoundedRectangle(cornerRadius: 9))
      .opacity(isEnabled ? 1 : 0.3)
      .animation(reduceMotion ? nil : IntervalMotion.selection, value: hovering)
      .animation(reduceMotion ? nil : IntervalMotion.selection, value: configuration.isPressed)
      .onHover { hovering = $0 }
  }
}

struct GlassBackground: View {
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  var body: some View {
    ZStack {
      NativeGlass(reduceTransparency: reduceTransparency)
      IntervalTheme.surface.opacity(reduceTransparency ? 1 : 0.58)
    }.ignoresSafeArea()
  }
}

private struct NativeGlass: NSViewRepresentable {
  let reduceTransparency: Bool
  func makeNSView(context: Context) -> NSVisualEffectView {
    let view = NSVisualEffectView()
    view.material = .hudWindow
    view.blendingMode = .behindWindow
    view.state = .active
    return view
  }
  func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
    DispatchQueue.main.async {
      guard let window = nsView.window else { return }
      window.isOpaque = reduceTransparency
      window.backgroundColor = reduceTransparency ? NSColor(IntervalTheme.surface) : .clear
      window.titlebarAppearsTransparent = true
    }
  }
}

struct IntervalPrimaryButton: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var hovering = false
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 14, weight: .semibold))
      .foregroundStyle(Color.primary.opacity(isEnabled ? 0.9 : 0.45))
      .padding(.horizontal, 14).padding(.vertical, 7)
      .background(
        Color.accentColor.opacity(configuration.isPressed ? 0.4 : hovering ? 0.32 : 0.25),
        in: RoundedRectangle(cornerRadius: 8)
      )
      .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(IntervalTheme.border) }
      .opacity(isEnabled ? 1 : 0.5)
      .contentShape(RoundedRectangle(cornerRadius: 8))
      .animation(reduceMotion ? nil : IntervalMotion.selection, value: hovering)
      .animation(reduceMotion ? nil : IntervalMotion.selection, value: configuration.isPressed)
      .onHover { hovering = $0 }
  }
}
