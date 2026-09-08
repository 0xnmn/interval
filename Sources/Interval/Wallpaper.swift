import AppKit
import CoreGraphics
import CoreImage
import ScreenCaptureKit

enum WallpaperCaptureAvailability: Equatable {
  case available
  case permissionRequired
}

/// Loads the wallpaper actually composited by macOS, including dynamic and per-display wallpapers.
/// ScreenCaptureKit is restricted to a single, identified Wallpaper window so application content is
/// never part of the capture.
@MainActor enum Wallpaper {
  struct WindowDescription: Equatable {
    let bundleIdentifier: String
    let frame: CGRect
    var layer: Int = 0
  }

  static var captureAvailability: WallpaperCaptureAvailability {
    CGPreflightScreenCaptureAccess() ? .available : .permissionRequired
  }

  static func image(for screen: NSScreen) async -> NSImage? {
    let fallback = staticImage(for: screen)
    guard captureAvailability == .available else { return fallback }

    do {
      let content = try await SCShareableContent.excludingDesktopWindows(
        false, onScreenWindowsOnly: true)
      let displayBounds = CGDisplayBounds(screen.displayID)
      guard
        let window = content.windows.first(where: {
          isWallpaperWindow(
            WindowDescription(
              bundleIdentifier: $0.owningApplication?.bundleIdentifier ?? "",
              frame: $0.frame, layer: $0.windowLayer),
            for: displayBounds)
        })
      else { return fallback }

      // A desktop-independent window filter captures this window alone, regardless of what is in
      // front of it. Do not replace this with display or rectangle capture.
      let filter = SCContentFilter(desktopIndependentWindow: window)
      let configuration = SCStreamConfiguration()
      let scale = min(1, 1600 / max(window.frame.width, window.frame.height))
      configuration.width = Int(window.frame.width * scale)
      configuration.height = Int(window.frame.height * scale)
      configuration.showsCursor = false
      configuration.ignoreShadowsSingleWindow = true
      let captured = try await SCScreenshotManager.captureImage(
        contentFilter: filter, configuration: configuration)
      return blurredImage(captured)
    } catch {
      return fallback
    }
  }

  static func staticImage(for screen: NSScreen) -> NSImage? {
    guard let url = NSWorkspace.shared.desktopImageURL(for: screen),
      let image = CIImage(contentsOf: url), !image.extent.isEmpty
    else { return nil }
    return blurredImage(image)
  }

  static func isWallpaperWindow(_ window: WindowDescription, for displayBounds: CGRect) -> Bool {
    let bundleID = window.bundleIdentifier.lowercased()
    // Static wallpapers are composited by Dock below the desktop level on modern macOS.
    // Never select its normal Dock, Launchpad, or application-preview windows.
    let desktopBackdrop =
      bundleID == "com.apple.dock"
      && window.layer == Int(CGWindowLevelForKey(.desktopWindow)) - 1
    guard bundleID == "com.apple.wallpaper.agent" || desktopBackdrop else { return false }

    // ScreenCaptureKit and CGDisplayBounds both use the global display coordinate system. Allow a
    // point for compositor rounding, but never accept a window that merely overlaps the display.
    return abs(window.frame.minX - displayBounds.minX) <= 1
      && abs(window.frame.minY - displayBounds.minY) <= 1
      && abs(window.frame.width - displayBounds.width) <= 1
      && abs(window.frame.height - displayBounds.height) <= 1
  }

  private static func blurredImage(_ image: CIImage) -> NSImage? {
    let scale = min(1, 1600 / max(image.extent.width, image.extent.height))
    let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    let blurred = scaled.clampedToExtent()
      .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 60])
      .cropped(to: scaled.extent)
    guard let rendered = CIContext().createCGImage(blurred, from: scaled.extent) else { return nil }
    return NSImage(cgImage: rendered, size: scaled.extent.size)
  }

  private static func blurredImage(_ image: CGImage) -> NSImage? {
    blurredImage(CIImage(cgImage: image))
  }
}

extension NSScreen {
  fileprivate var displayID: CGDirectDisplayID {
    deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
  }
}
