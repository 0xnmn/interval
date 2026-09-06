import AppKit
import IntervalCore
import SwiftUI

enum IntervalTheme {
  static let accent = Color.accentColor
  static let surface = Color(white: 0.12)
  static let border = Color.white.opacity(0.07)
  static let body = Font.system(size: 14)
  static let heading = Font.system(size: 14, weight: .semibold)
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
  @State private var hovering = false

  func makeBody(configuration: Configuration) -> some View {
    configuration.label.labelStyle(.iconOnly)
      .font(.system(size: 17, weight: .medium))
      .frame(width: 36, height: 36)
      .background(
        .white.opacity(configuration.isPressed ? 0.18 : hovering ? 0.12 : 0.06),
        in: RoundedRectangle(cornerRadius: 9)
      )
      .contentShape(RoundedRectangle(cornerRadius: 9))
      .opacity(isEnabled ? 1 : 0.3)
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
    view.appearance = NSAppearance(named: .darkAqua)
    return view
  }
  func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
    DispatchQueue.main.async {
      guard let window = nsView.window else { return }
      window.isOpaque = reduceTransparency
      window.backgroundColor = reduceTransparency ? NSColor(IntervalTheme.surface) : .clear
      window.appearance = NSAppearance(named: .darkAqua)
      window.titlebarAppearsTransparent = true
    }
  }
}

struct IntervalPrimaryButton: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.callout.weight(.semibold))
      .foregroundStyle(Color.white.opacity(isEnabled ? 0.9 : 0.45))
      .padding(.horizontal, 14).padding(.vertical, 7)
      .background(
        Color.accentColor.opacity(configuration.isPressed ? 0.4 : 0.25),
        in: RoundedRectangle(cornerRadius: 8)
      )
      .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.12)) }
      .opacity(isEnabled ? 1 : 0.5)
      .contentShape(RoundedRectangle(cornerRadius: 8))
  }
}
