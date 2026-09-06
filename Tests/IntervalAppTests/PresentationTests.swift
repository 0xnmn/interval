import AppKit
import Foundation
import IntervalCore
import SwiftUI
import Testing

@testable import Interval

@MainActor struct PresentationTests {
  @Test func upcomingSuppressionOnlyDescribesOverlappingDueTimes() {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let now = SnapshotRenderer.fixtureNow
    let service = CalendarService(fixtureEvents: [
      CalendarEventSnapshot(
        id: "meeting", title: "Meeting", start: now.addingTimeInterval(-60),
        end: now.addingTimeInterval(300), allDay: false, calendarName: "Work"),
      CalendarEventSnapshot(
        id: "later", title: "Later meeting", start: now.addingTimeInterval(900),
        end: now.addingTimeInterval(1200), allDay: false, calendarName: "Work"),
    ])
    let store = AppStore(
      persistence: JSONStore(fileURL: directory.appendingPathComponent("state.json")),
      calendarService: service, runtimeEnabled: false)
    store.now = now
    service.configure(enabled: true, selectedCalendarIDs: ["Work"])
    _ = service.hasEvent(at: now)
    var reminder = Reminder(title: "Water", dueAt: now.addingTimeInterval(600))
    reminder.suppressDuringFocus = false
    reminder.suppressDuringCalendar = true
    let view = UpcomingReminders(store: store)
    #expect(view.reminderStatus(reminder) == "In 10:00")
    reminder.dueAt = now.addingTimeInterval(60)
    #expect(view.reminderStatus(reminder) == "After event")
    reminder.suppressDuringCalendar = false
    reminder.suppressDuringFocus = true
    store.data.activeTimer = TimerState(
      kind: .focus, duration: 300, status: .running,
      startedAt: now, deadline: now.addingTimeInterval(300))
    #expect(view.reminderStatus(reminder) == "After focus")
    reminder.dueAt = now.addingTimeInterval(600)
    #expect(view.reminderStatus(reminder) == "In 10:00")
    reminder.suppressDuringCalendar = true
    reminder.dueAt = now.addingTimeInterval(1000)
    #expect(view.reminderStatus(reminder) == "After event")
    store.data.activeTimer?.deadline = now.addingTimeInterval(1500)
    #expect(view.reminderStatus(reminder) == "After focus")
  }

  @Test func appearanceMigratesAndPersistsWithoutResettingTimer() throws {
    let legacy = Data(
      """
      {"focusMinutes":25,"shortBreakMinutes":5,"longBreakMinutes":10,"longBreakEvery":4}
      """.utf8)
    #expect(try JSONDecoder().decode(IntervalSettings.self, from: legacy).appearance == .system)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let persistence = JSONStore(fileURL: directory.appendingPathComponent("state.json"))
    let store = AppStore(persistence: persistence, runtimeEnabled: false)
    let timer = store.timer
    for appearance in AppAppearance.allCases {
      var settings = store.data.settings
      settings.appearance = appearance
      store.updateSettings(settings)
      #expect(store.timer == timer)
      #expect(try persistence.load().settings.appearance == appearance)
      #expect(settings.clamped().appearance == appearance)
    }
    store.startSession()
    let running = store.timer
    var settings = store.data.settings
    settings.appearance = .light
    store.updateSettings(settings)
    #expect(store.timer == running)
  }

  @Test func existingNativeWindowsInheritAppearanceChanges() {
    let original = NSApplication.shared.appearance
    defer { NSApplication.shared.appearance = original }
    let window = NSWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: false)
    let panel = NSPanel(
      contentRect: .zero, styleMask: [.nonactivatingPanel], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    panel.isReleasedWhenClosed = false
    defer {
      window.close()
      panel.close()
    }
    window.contentView = NSHostingView(rootView: GlassBackground())
    panel.contentView = NSHostingView(rootView: Text("Reminder"))
    for appearance in [AppAppearance.light, .dark, .system] {
      appearance.apply()
      let expected = NSApplication.shared.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])
      for surface in [window, panel] {
        #expect(surface.appearance == nil)
        #expect(
          surface.contentView?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == expected)
      }
    }
    #expect(NSApplication.shared.appearance == nil)
  }

  @Test func nativeAppearanceAndSurfaceAdapt() {
    #expect(AppAppearance.system.nativeAppearance == nil)
    #expect(AppAppearance.light.nativeAppearance?.name == .aqua)
    #expect(AppAppearance.dark.nativeAppearance?.name == .darkAqua)
    var light: CGFloat = 0
    var dark: CGFloat = 1
    AppAppearance.light.nativeAppearance!.performAsCurrentDrawingAppearance {
      light = NSColor(IntervalTheme.surface).usingColorSpace(.deviceRGB)!.redComponent
    }
    AppAppearance.dark.nativeAppearance!.performAsCurrentDrawingAppearance {
      dark = NSColor(IntervalTheme.surface).usingColorSpace(.deviceRGB)!.redComponent
    }
    #expect(light > 0.9)
    #expect(dark < 0.2)
  }

  @Test func dialUsesSixtyMinuteScale() {
    #expect(FocusDial.fraction(for: 1_500) == 25.0 / 60)
    #expect(FocusDial.fraction(for: 300) == 5.0 / 60)
    #expect(FocusDial.fraction(for: 3_600) == 1)
    #expect(FocusDial.fraction(for: 0) == 0)
  }

  @Test func reminderCounterUsesActualElapsedTimeAndStopsAtZero() {
    let reminder = Reminder(title: "Look away", displaySeconds: 20, presentation: .fullscreen)
    let start = Date(timeIntervalSince1970: 1_000)
    for (elapsed, expected) in [(0.0, 20), (1, 19), (5.25, 15), (19.9, 1), (20, 0), (30, 0)] {
      #expect(
        ReminderTakeoverView.remainingSeconds(
          reminder: reminder, shownAt: start, now: start.addingTimeInterval(elapsed)) == expected)
    }
  }
}
