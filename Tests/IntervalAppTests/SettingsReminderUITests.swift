import AppKit
import IntervalCore
import SwiftUI
import Testing

@testable import Interval

@MainActor @Suite("Settings and reminder native UI", .serialized)
struct SettingsReminderUITests {
  @Test func settingsSidebarArrowDownSelectsSound() async throws {
    let store = try makeStore()
    defer { try? FileManager.default.removeItem(at: store.storageURL.deletingLastPathComponent()) }
    let harness = try await NativeViewHarness(
      rootView: AnyView(SettingsView(store: store)))
    defer { harness.close() }

    let sidebar = try #require(harness.descendants.compactMap { $0 as? NSTableView }.first)
    sidebar.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
    guard harness.window.makeFirstResponder(sidebar) else { throw UITestError.couldNotFocus }
    await harness.send(keyCode: 125, characters: "\u{f701}")

    #expect(sidebar.selectedRow == 1)
    #expect(harness.descendants.contains { $0 is NSSlider })
  }

  @Test func reminderTitleEditingPersistsThroughNativeEditor() async throws {
    let reminder = Reminder(title: "Original title")
    let store = try makeStore(reminders: [reminder])
    defer { try? FileManager.default.removeItem(at: store.storageURL.deletingLastPathComponent()) }
    let harness = try await NativeViewHarness(
      rootView: AnyView(
        RemindersView(store: store, selection: reminder.id).frame(width: 760, height: 520)))
    defer { harness.close() }

    let title = try harness.titleEditor(value: reminder.title)
    try await harness.replaceText(in: title, with: "Persisted title")
    guard harness.window.makeFirstResponder(nil) else { throw UITestError.couldNotFocus }
    await harness.pump()

    #expect(store.data.reminders[0].title == "Persisted title")
    let saved = try JSONStore(fileURL: store.storageURL).load()
    #expect(saved.reminders.first(where: { $0.id == reminder.id })?.title == "Persisted title")
  }

  private func makeStore(reminders: [Reminder] = []) throws -> AppStore {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let store = AppStore(
      persistence: JSONStore(fileURL: directory.appendingPathComponent("data.json")),
      calendarService: CalendarService(fixtureEvents: []), runtimeEnabled: false)
    store.data.reminders = reminders
    return store
  }
}

@MainActor
private final class NativeViewHarness {
  let window: NSWindow

  init(rootView: AnyView) async throws {
    _ = NSApplication.shared
    let hostingView = NSHostingView(rootView: rootView)
    window = NSWindow(
      contentRect: NSRect(x: 100, y: 100, width: 800, height: 560),
      styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = hostingView
    window.makeKeyAndOrderFront(nil)
    await pump()
    guard window.contentView != nil else { throw UITestError.noHostedContent }
  }

  var descendants: [NSView] {
    guard let content = window.contentView else { return [] }
    return descendants(of: content)
  }

  func titleEditor(value: String) throws -> NSTextField {
    guard
      let field = descendants.compactMap({ $0 as? NSTextField }).first(where: {
        $0.isEditable && $0.stringValue == value
      })
    else { throw UITestError.noTitleEditor }
    return field
  }

  func replaceText(in field: NSTextField, with value: String) async throws {
    guard window.makeFirstResponder(field), let editor = field.currentEditor() as? NSTextView else {
      throw UITestError.couldNotFocus
    }
    editor.setSelectedRange(NSRange(location: 0, length: editor.string.utf16.count))
    await send(keyCode: 0, characters: value)
  }

  func send(keyCode: UInt16, characters: String) async {
    let event = NSEvent.keyEvent(
      with: .keyDown, location: .zero, modifierFlags: [],
      timestamp: ProcessInfo.processInfo.systemUptime,
      windowNumber: window.windowNumber, context: nil, characters: characters,
      charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode)!
    window.sendEvent(event)
    await pump()
  }

  func pump() async {
    for _ in 0..<3 {
      await Task.yield()
      try? await Task.sleep(for: .milliseconds(35))
      window.contentView?.layoutSubtreeIfNeeded()
    }
  }

  func close() {
    window.orderOut(nil)
    window.close()
  }

  private func descendants(of view: NSView) -> [NSView] {
    view.subviews.flatMap { [$0] + descendants(of: $0) }
  }

}

private enum UITestError: Error {
  case noHostedContent
  case couldNotFocus
  case noTitleEditor
}
