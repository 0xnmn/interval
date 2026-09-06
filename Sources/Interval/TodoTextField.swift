import AppKit
import SwiftUI

// Handle editing commands in the field editor, before it consumes Backspace and arrows.
struct TodoTextField: NSViewRepresentable {
  @Binding var text: String
  let completed: Bool
  let isFocused: Bool
  let onFocus: () -> Void
  let onBlur: () -> Void
  let onSubmit: () -> Void
  let onDeleteEmpty: () -> Void
  let onMove: (Int) -> Void

  func makeCoordinator() -> Coordinator { Coordinator(self) }

  func makeNSView(context: Context) -> NSTextField {
    let field = NSTextField(wrappingLabelWithString: text)
    field.isEditable = true
    field.isSelectable = true
    field.isBordered = false
    field.focusRingType = .none
    field.drawsBackground = false
    field.font = .systemFont(ofSize: 14)
    field.placeholderString = "To-do"
    field.maximumNumberOfLines = 5
    field.delegate = context.coordinator
    field.setAccessibilityLabel("To-do title")
    field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    return field
  }

  func updateNSView(_ field: NSTextField, context: Context) {
    let coordinator = context.coordinator
    coordinator.parent = self
    if field.stringValue != text { field.stringValue = text }
    field.textColor = completed ? .secondaryLabelColor : .labelColor
    if field.currentEditor() == nil {
      field.attributedStringValue = NSAttributedString(
        string: text,
        attributes: [
          .font: field.font!, .foregroundColor: field.textColor!,
          .strikethroughStyle: completed ? NSUnderlineStyle.single.rawValue : 0,
        ])
    }
    if isFocused && !coordinator.requestedFocus {
      DispatchQueue.main.async { [weak field, weak coordinator] in
        guard let field, coordinator?.parent.isFocused == true,
          let window = field.window
        else { return }
        if field.currentEditor() == nil { window.makeFirstResponder(field) }
        field.scrollToVisible(field.bounds)
      }
    }
    coordinator.requestedFocus = isFocused
  }

  func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSTextField, context: Context) -> CGSize?
  {
    guard let width = proposal.width else { return nil }
    let bounds = NSRect(x: 0, y: 0, width: width, height: .greatestFiniteMagnitude)
    let size = nsView.cell?.cellSize(forBounds: bounds) ?? .zero
    return CGSize(width: width, height: max(20, size.height))
  }

  final class Coordinator: NSObject, NSTextFieldDelegate {
    var parent: TodoTextField
    var requestedFocus = false
    init(_ parent: TodoTextField) { self.parent = parent }

    func controlTextDidBeginEditing(_ obj: Notification) { parent.onFocus() }
    func controlTextDidEndEditing(_ obj: Notification) { parent.onBlur() }
    func controlTextDidChange(_ obj: Notification) {
      guard let field = obj.object as? NSTextField else { return }
      parent.text = field.stringValue
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector)
      -> Bool
    {
      // Let input methods confirm their marked text before interpreting checklist commands.
      guard !textView.hasMarkedText() else { return false }
      switch commandSelector {
      case #selector(NSResponder.insertNewline(_:)):
        parent.onSubmit()
      case #selector(NSResponder.deleteBackward(_:)):
        guard textView.string.isEmpty else {
          return false
        }
        parent.onDeleteEmpty()
      case #selector(NSResponder.moveUp(_:)):
        guard isOnBoundaryVisualLine(textView, first: true) else { return false }
        parent.onMove(-1)
      case #selector(NSResponder.moveDown(_:)):
        guard isOnBoundaryVisualLine(textView, first: false) else { return false }
        parent.onMove(1)
      default: return false
      }
      return true
    }

    private func isOnBoundaryVisualLine(_ textView: NSTextView, first: Bool) -> Bool {
      guard let layoutManager = textView.layoutManager,
        let textContainer = textView.textContainer
      else { return true }

      layoutManager.ensureLayout(for: textContainer)
      let glyphRange = layoutManager.glyphRange(for: textContainer)
      guard glyphRange.length > 0 else { return true }

      let characterLocation = min(textView.selectedRange().location, textView.string.utf16.count)
      let glyphIndex =
        characterLocation == textView.string.utf16.count
        ? NSMaxRange(glyphRange) - 1
        : layoutManager.glyphIndexForCharacter(at: characterLocation)
      var lineRange = NSRange()
      layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &lineRange)
      return first
        ? lineRange.location == glyphRange.location
        : NSMaxRange(lineRange) == NSMaxRange(glyphRange)
    }
  }
}
