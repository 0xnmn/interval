import AppKit
import SwiftUI

enum IntervalTheme {
  static let accent = Color(white: 0.88)
  static let surface = Color(white: 0.12)
  static let border = Color.white.opacity(0.07)
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
        Color.white.opacity(configuration.isPressed ? 0.18 : 0.10),
        in: RoundedRectangle(cornerRadius: 8)
      )
      .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.12)) }
      .opacity(isEnabled ? 1 : 0.5)
      .contentShape(RoundedRectangle(cornerRadius: 8))
  }
}
