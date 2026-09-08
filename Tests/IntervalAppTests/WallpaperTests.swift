import CoreGraphics
import Testing

@testable import Interval

@MainActor struct WallpaperTests {
  @Test func matchesOnlyWallpaperWindowCoveringRequestedDisplay() {
    let display = CGRect(x: 2560, y: 0, width: 2560, height: 1440)
    #expect(
      Wallpaper.isWallpaperWindow(
        .init(
          bundleIdentifier: "com.apple.dock", frame: display,
          layer: Int(CGWindowLevelForKey(.desktopWindow)) - 1), for: display))
    #expect(
      !Wallpaper.isWallpaperWindow(
        .init(
          bundleIdentifier: "com.apple.dock", frame: display,
          layer: Int(CGWindowLevelForKey(.dockWindow))), for: display))

    #expect(
      Wallpaper.isWallpaperWindow(
        .init(
          bundleIdentifier: "com.apple.wallpaper.agent", frame: display), for: display))
    #expect(
      !Wallpaper.isWallpaperWindow(
        .init(
          bundleIdentifier: "com.example.private", frame: display), for: display))
    #expect(
      !Wallpaper.isWallpaperWindow(
        .init(
          bundleIdentifier: "com.apple.wallpaper.agent",
          frame: CGRect(x: 0, y: 0, width: 2560, height: 1440)), for: display))
  }

  @Test func toleratesOnlyCompositorRounding() {
    let display = CGRect(x: 0, y: 0, width: 2560, height: 1440)
    #expect(
      Wallpaper.isWallpaperWindow(
        .init(
          bundleIdentifier: "com.apple.wallpaper.agent",
          frame: CGRect(x: 0.5, y: -0.5, width: 2559.5, height: 1440.5)), for: display))
    #expect(
      !Wallpaper.isWallpaperWindow(
        .init(
          bundleIdentifier: "com.apple.wallpaper.agent",
          frame: display.insetBy(dx: 2, dy: 2)), for: display))
  }
}
