import AppKit
import SwiftUI

/// Native resizing and accessibility, with the same separator as the rest of the app.
struct ThemedSplitView<First: View, Second: View>: NSViewControllerRepresentable {
  let isVertical: Bool
  let minimumFirst: CGFloat
  var maximumFirst: CGFloat? = nil
  let minimumSecond: CGFloat
  @ViewBuilder var first: First
  @ViewBuilder var second: Second

  func makeNSViewController(context: Context) -> NSSplitViewController {
    let controller = NSSplitViewController()
    let split = ThemeSplitView()
    split.isVertical = isVertical
    split.dividerStyle = .thin
    controller.splitView = split
    let leading = NSSplitViewItem(viewController: NSHostingController(rootView: first))
    leading.minimumThickness = minimumFirst
    if let maximumFirst { leading.maximumThickness = maximumFirst }
    leading.canCollapse = false
    let trailing = NSSplitViewItem(viewController: NSHostingController(rootView: second))
    trailing.minimumThickness = minimumSecond
    trailing.canCollapse = false
    controller.addSplitViewItem(leading)
    controller.addSplitViewItem(trailing)
    return controller
  }

  func updateNSViewController(_ controller: NSSplitViewController, context: Context) {
    (controller.splitViewItems[0].viewController as? NSHostingController<First>)?.rootView = first
    (controller.splitViewItems[1].viewController as? NSHostingController<Second>)?.rootView = second
  }

  func sizeThatFits(
    _ proposal: ProposedViewSize, nsViewController: NSSplitViewController, context: Context
  ) -> CGSize? {
    proposal.replacingUnspecifiedDimensions()
  }
}

final class ThemeSplitView: NSSplitView {
  override var dividerColor: NSColor { NSColor.labelColor.withAlphaComponent(0.07) }

  override func drawDivider(in rect: NSRect) {
    dividerColor.setFill()
    rect.fill()
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    needsDisplay = true
  }
}
