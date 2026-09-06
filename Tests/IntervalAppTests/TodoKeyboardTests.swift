import AppKit
import IntervalCore
import SwiftUI
import Testing

@testable import Interval

@MainActor @Suite("To-do keyboard editing", .serialized)
struct TodoKeyboardTests {
  @Test func returnAndBackspaceMutateRowsAndMoveNativeFocus() async throws {
    let harness = try await Harness(titles: ["First"])
    defer { harness.close() }

    try await harness.focusRow(0)
    await harness.send(keyCode: 36, characters: "\r")
    #expect(harness.store.data.todos.map(\.title) == ["First", ""])
    #expect(try harness.focusedRow() == 1)

    await harness.send(keyCode: 51, characters: "\u{7f}")
    #expect(harness.store.data.todos.map(\.title) == ["First"])
    #expect(try harness.focusedRow() == 0)

    harness.store.updateTodoTitle(harness.store.data.todos[0].id, title: "")
    await harness.pump()
    await harness.send(keyCode: 51, characters: "\u{7f}")
    #expect(harness.store.data.todos.count == 1)
    #expect(harness.store.data.todos[0].title.isEmpty)
    #expect(try harness.focusedRow() == 0)
  }

  @Test func arrowsNavigateAndTypingEditsOnlyFocusedRow() async throws {
    let harness = try await Harness(titles: ["Alpha", "Beta", "Gamma"])
    defer { harness.close() }

    try await harness.focusRow(1)
    await harness.send(keyCode: 126, characters: "\u{f700}")
    #expect(try harness.focusedRow() == 0)
    await harness.send(keyCode: 125, characters: "\u{f701}")
    #expect(try harness.focusedRow() == 1)

    harness.moveInsertionPointToEnd()
    await harness.send(keyCode: 0, characters: "!")
    #expect(harness.store.data.todos.map(\.title) == ["Alpha", "Beta!", "Gamma"])
    #expect(try harness.focusedRow() == 1)
  }

  @Test func arrowsMoveThroughWrappedTextBeforeNavigatingRows() async throws {
    let wrapped = Array(repeating: "wrapped keyboard navigation", count: 8).joined(separator: " ")
    let harness = try await Harness(titles: ["Before", wrapped, "After"])
    defer { harness.close() }

    try await harness.focusRow(1)
    harness.moveInsertionPoint(to: 0)
    await harness.send(keyCode: 125, characters: "\u{f701}")
    #expect(try harness.focusedRow() == 1)
    #expect(harness.insertionPoint() > 0)

    await harness.send(keyCode: 126, characters: "\u{f700}")
    #expect(try harness.focusedRow() == 1)
    await harness.send(keyCode: 126, characters: "\u{f700}")
    #expect(try harness.focusedRow() == 0)

    try await harness.focusRow(1)
    harness.moveInsertionPoint(to: wrapped.utf16.count)
    await harness.send(keyCode: 126, characters: "\u{f700}")
    #expect(try harness.focusedRow() == 1)
    #expect(harness.insertionPoint() < wrapped.utf16.count)

    await harness.send(keyCode: 125, characters: "\u{f701}")
    #expect(try harness.focusedRow() == 1)
    await harness.send(keyCode: 125, characters: "\u{f701}")
    #expect(try harness.focusedRow() == 2)
  }

  @Test func backspaceEditsWhitespaceBeforeDeletingEmptyRow() async throws {
    let harness = try await Harness(titles: ["First", "  "])
    defer { harness.close() }
    try await harness.focusRow(1)
    harness.moveInsertionPointToEnd()
    await harness.send(keyCode: 51, characters: "\u{7f}")
    #expect(harness.store.data.todos.map(\.title) == ["First", " "])
    await harness.send(keyCode: 51, characters: "\u{7f}")
    #expect(harness.store.data.todos.map(\.title) == ["First", ""])
    await harness.send(keyCode: 51, characters: "\u{7f}")
    #expect(harness.store.data.todos.map(\.title) == ["First"])
    #expect(try harness.focusedRow() == 0)
  }
}

@MainActor
private final class Harness {
  let store: AppStore
  private let directory: URL
  private let window: NSWindow

  init(titles: [String]) async throws {
    _ = NSApplication.shared
    directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    store = AppStore(
      persistence: JSONStore(fileURL: directory.appendingPathComponent("data.json")),
      runtimeEnabled: false)
    store.data.todos = titles.map { TodoItem(title: $0) }

    let hostingView = NSHostingView(rootView: TodoList(store: store).frame(width: 420))
    window = NSWindow(
      contentRect: NSRect(x: 100, y: 100, width: 440, height: 300),
      styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = hostingView
    window.makeKeyAndOrderFront(nil)
    await pump()
    _ = try editableRows().first ?? { throw TodoKeyboardTestError.noNativeEditor }()
  }

  func close() {
    window.orderOut(nil)
    window.close()
    try? FileManager.default.removeItem(at: directory)
  }

  func focusRow(_ index: Int) async throws {
    let row = editableRows()[index]
    #expect(row.focusRingType == .none)
    guard window.makeFirstResponder(row) else { throw TodoKeyboardTestError.couldNotFocus }
    await pump()
  }

  func focusedRow() throws -> Int {
    let rows = editableRows()
    guard let responder = window.firstResponder else { throw TodoKeyboardTestError.noFocusedEditor }
    if let index = rows.firstIndex(where: { $0 === responder }) { return index }
    if let editor = responder as? NSTextView,
      let field = editor.delegate as? NSView,
      let index = rows.firstIndex(where: { $0 === field })
    {
      return index
    }
    throw TodoKeyboardTestError.noFocusedEditor
  }

  func moveInsertionPoint(to location: Int) {
    if let editor = window.firstResponder as? NSTextView {
      editor.setSelectedRange(NSRange(location: location, length: 0))
    } else if let field = window.firstResponder as? NSTextField {
      (field.currentEditor() as? NSTextView)?.setSelectedRange(
        NSRange(location: location, length: 0))
    }
  }

  func moveInsertionPointToEnd() {
    if let editor = window.firstResponder as? NSTextView {
      moveInsertionPoint(to: editor.string.utf16.count)
    } else if let field = window.firstResponder as? NSTextField {
      moveInsertionPoint(to: field.stringValue.utf16.count)
    }
  }

  func insertionPoint() -> Int {
    if let editor = window.firstResponder as? NSTextView {
      return editor.selectedRange().location
    }
    return ((window.firstResponder as? NSTextField)?.currentEditor() as? NSTextView)?
      .selectedRange().location ?? 0
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
    try? await Task.sleep(for: .milliseconds(100))
    window.contentView?.layoutSubtreeIfNeeded()
  }

  private func editableRows() -> [NSView] {
    guard let contentView = window.contentView else { return [] }
    let fields = descendants(of: contentView).compactMap { $0 as? NSTextField }.filter {
      $0.isEditable && $0.isEnabled
    }
    let editors: [NSView] =
      fields.isEmpty
      ? descendants(of: contentView).filter { view in
        if let field = view as? NSTextField { return field.isEditable && field.isEnabled }
        if let textView = view as? NSTextView { return textView.isEditable }
        return false
      } : fields
    return editors.sorted { lhs, rhs in
      let a = lhs.convert(lhs.bounds, to: contentView).midY
      let b = rhs.convert(rhs.bounds, to: contentView).midY
      return contentView.isFlipped ? a < b : a > b
    }
  }

  private func descendants(of view: NSView) -> [NSView] {
    view.subviews.flatMap { [$0] + descendants(of: $0) }
  }
}

private enum TodoKeyboardTestError: Error {
  case noNativeEditor
  case couldNotFocus
  case noFocusedEditor
}
