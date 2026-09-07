import AppKit
import Testing

@testable import Interval

@MainActor struct ThemeContrastTests {
  @Test func phaseForegroundPaletteMeetsSurfaceContrast() throws {
    let colors: [NSColor] = [
      .systemGreen, .systemBlue, .systemTeal, .systemOrange,
      .systemRed, .systemPink, .systemPurple,
    ]
    for name in [
      NSAppearance.Name.aqua, .darkAqua, .accessibilityHighContrastAqua,
      .accessibilityHighContrastDarkAqua,
    ] {
      let appearance = try #require(NSAppearance(named: name))
      let increased =
        name == .accessibilityHighContrastAqua || name == .accessibilityHighContrastDarkAqua
      let surface = IntervalTheme.surfaceNSColor(for: appearance)
      for color in colors {
        let foreground = phaseForegroundNSColor(
          base: color, appearance: appearance, increasedContrast: increased)
        let values = [luminance(foreground), luminance(surface)].sorted()
        #expect((values[1] + 0.05) / (values[0] + 0.05) >= (increased ? 7 : 4.5) - 0.001)
      }
      #expect(
        IntervalTheme.borderNSColor(for: appearance, increasedContrast: increased).alphaComponent
          == (increased ? 0.35 : 0.07))
    }
  }

  private func luminance(_ color: NSColor) -> CGFloat {
    let rgb = color.usingColorSpace(.sRGB)!
    func linear(_ value: CGFloat) -> CGFloat {
      value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * linear(rgb.redComponent) + 0.7152 * linear(rgb.greenComponent)
      + 0.0722 * linear(rgb.blueComponent)
  }
}
