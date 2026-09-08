import AppKit
import IntervalCore
import SwiftUI

enum IntervalTheme {
  static let accent = Color.accentColor
  static let surface = Color(
    nsColor: NSColor(name: nil) { appearance in
      surfaceNSColor(for: appearance)
    })
  static let border = Color(
    nsColor: NSColor(name: nil) { appearance in
      borderNSColor(for: appearance)
    })
  static let body = Font.system(size: 14)
  static let heading = Font.system(size: 14, weight: .semibold)
  static let icon = Font.system(size: 16, weight: .medium)

  static func surfaceNSColor(for appearance: NSAppearance) -> NSColor {
    NSColor(white: appearance.isDark ? 0.12 : 0.97, alpha: 1)
  }

  static func borderNSColor(for appearance: NSAppearance, increasedContrast: Bool? = nil) -> NSColor
  {
    NSColor(
      white: appearance.isDark ? 1 : 0,
      alpha: (increasedContrast ?? appearance.isHighContrast) ? 0.35 : 0.07)
  }
}

extension NSAppearance {
  fileprivate var isDark: Bool {
    bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
  }

  fileprivate var isHighContrast: Bool {
    name == .accessibilityHighContrastAqua || name == .accessibilityHighContrastDarkAqua
      || name == .accessibilityHighContrastVibrantLight
      || name == .accessibilityHighContrastVibrantDark
      || NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
  }
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

  /// A text/icon variant of the phase hue. Keep `color` for decorative fills and rings.
  var foregroundColor: Color {
    Color(
      nsColor: NSColor(name: nil) { appearance in
        phaseForegroundNSColor(base: nsColor, appearance: appearance)
      })
  }

  private var nsColor: NSColor {
    switch self {
    case .green: .systemGreen
    case .blue: .systemBlue
    case .teal: .systemTeal
    case .orange: .systemOrange
    case .red: .systemRed
    case .pink: .systemPink
    case .purple: .systemPurple
    }
  }
}

/// Resolves a semantic hue to the nearest sRGB color meeting text contrast against the surface.
/// Internal visibility intentionally keeps the color math directly testable.
func phaseForegroundNSColor(base: NSColor, appearance: NSAppearance, increasedContrast: Bool? = nil)
  -> NSColor
{
  var resolved = base
  appearance.performAsCurrentDrawingAppearance { resolved = base.usingColorSpace(.sRGB) ?? base }
  let base = resolved
  let surface = IntervalTheme.surfaceNSColor(for: appearance).usingColorSpace(.sRGB)!
  let target: CGFloat = (increasedContrast ?? appearance.isHighContrast) ? 7 : 4.5
  guard contrastRatio(base, surface) < target else { return base }

  let destination = NSColor(white: appearance.isDark ? 1 : 0, alpha: 1)
  var low: CGFloat = 0
  var high: CGFloat = 1
  for _ in 0..<16 {
    let midpoint = (low + high) / 2
    if contrastRatio(blend(base, toward: destination, amount: midpoint), surface) >= target {
      high = midpoint
    } else {
      low = midpoint
    }
  }
  return blend(base, toward: destination, amount: high)
}

private func blend(_ color: NSColor, toward destination: NSColor, amount: CGFloat) -> NSColor {
  let color = color.usingColorSpace(.sRGB)!
  let destination = destination.usingColorSpace(.sRGB)!
  return NSColor(
    srgbRed: color.redComponent + (destination.redComponent - color.redComponent) * amount,
    green: color.greenComponent + (destination.greenComponent - color.greenComponent) * amount,
    blue: color.blueComponent + (destination.blueComponent - color.blueComponent) * amount,
    alpha: color.alphaComponent)
}

private func contrastRatio(_ lhs: NSColor, _ rhs: NSColor) -> CGFloat {
  func luminance(_ color: NSColor) -> CGFloat {
    let color = color.usingColorSpace(.sRGB)!
    func linear(_ value: CGFloat) -> CGFloat {
      value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * linear(color.redComponent) + 0.7152 * linear(color.greenComponent)
      + 0.0722 * linear(color.blueComponent)
  }
  let values = [luminance(lhs), luminance(rhs)].sorted()
  return (values[1] + 0.05) / (values[0] + 0.05)
}

struct IntervalSelectionButton: ButtonStyle {
  let selected: Bool
  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var hovering = false

  init(selected: Bool = false) { self.selected = selected }

  func makeBody(configuration: Configuration) -> some View {
    let active = isEnabled && (hovering || configuration.isPressed)
    configuration.label
      .foregroundStyle(selected ? Color.accentColor : Color.secondary)
      .background(
        Color.primary.opacity(active ? (configuration.isPressed ? 0.14 : 0.08) : 0),
        in: RoundedRectangle(cornerRadius: 8)
      )
      .contentShape(RoundedRectangle(cornerRadius: 8))
      .opacity(isEnabled ? 1 : 0.45)
      .animation(reduceMotion ? nil : IntervalMotion.selection, value: active)
      .animation(reduceMotion ? nil : IntervalMotion.selection, value: selected)
      .onHover { hovering = $0 }
  }
}

struct IntervalOutlineButton: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled
  @State private var hovering = false

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(IntervalTheme.body)
      .foregroundStyle(Color.accentColor)
      .padding(.horizontal, 14).padding(.vertical, 8)
      .background(
        Color.accentColor.opacity(configuration.isPressed ? 0.12 : hovering ? 0.06 : 0),
        in: RoundedRectangle(cornerRadius: 8)
      )
      .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor.opacity(0.6)))
      .contentShape(RoundedRectangle(cornerRadius: 8))
      .opacity(isEnabled ? 1 : 0.45)
      .onHover { hovering = $0 }
  }
}

struct IntervalIconButton: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.colorSchemeContrast) private var contrast
  private var increaseContrast: Bool { contrast == .increased }
  @State private var hovering = false

  func makeBody(configuration: Configuration) -> some View {
    configuration.label.labelStyle(.iconOnly)
      .font(IntervalTheme.icon)
      .frame(width: 36, height: 36)
      .modifier(
        InteractiveGlass(
          shape: RoundedRectangle(cornerRadius: 9),
          opaque: reduceTransparency || increaseContrast)
      )
      .background(
        Color.primary.opacity(
          configuration.isPressed
            ? (increaseContrast ? 0.26 : 0.18)
            : hovering ? (increaseContrast ? 0.18 : 0.12) : (increaseContrast ? 0.1 : 0.06)),
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
  @Environment(\.colorSchemeContrast) private var contrast
  private var increaseContrast: Bool { contrast == .increased }
  var body: some View {
    let opaque = reduceTransparency || increaseContrast
    ZStack {
      NativeGlass(opaque: opaque)
      IntervalTheme.surface.opacity(opaque ? 1 : 0.58)
    }.ignoresSafeArea()
  }
}

private struct NativeGlass: NSViewRepresentable {
  let opaque: Bool
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
      window.isOpaque = opaque
      window.backgroundColor = opaque ? NSColor(IntervalTheme.surface) : .clear
      window.titlebarAppearsTransparent = true
    }
  }
}

struct IntervalPrimaryButton: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.colorSchemeContrast) private var contrast
  private var increaseContrast: Bool { contrast == .increased }
  @State private var hovering = false
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 14, weight: .semibold))
      .foregroundStyle(Color.primary.opacity(isEnabled ? (increaseContrast ? 1 : 0.9) : 0.45))
      .padding(.horizontal, 14).padding(.vertical, 7)
      .modifier(
        InteractiveGlass(
          shape: RoundedRectangle(cornerRadius: 8),
          tint: .accentColor,
          opaque: reduceTransparency || increaseContrast)
      )
      .background(
        Color.accentColor.opacity(
          configuration.isPressed
            ? (increaseContrast ? 0.5 : 0.4)
            : hovering ? (increaseContrast ? 0.42 : 0.32) : (increaseContrast ? 0.34 : 0.25)),
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

private struct InteractiveGlass<S: Shape>: ViewModifier {
  let shape: S
  var tint: Color? = nil
  let opaque: Bool

  @ViewBuilder func body(content: Content) -> some View {
    if opaque {
      content.background(IntervalTheme.surface, in: shape)
    } else {
      content.glassEffect(.regular.tint(tint).interactive(), in: shape)
    }
  }
}
