import Foundation
import SwiftUI

/// An occurrence's identity survives idle deadline shifts. Moving it outside the
/// one-minute window (including an explicit extension) arms its next heads-up.
struct NotchHeadsUp: Equatable {
  enum Target: Hashable {
    case focus(UUID)
    case reminder(UUID)
  }
  let target: Target
  let deadline: Date
  let title: String
  let symbol: String
  var eligible = true

  var statusTitle: String {
    switch target {
    case .focus: "Focus ends soon"
    case .reminder: "Reminder coming up"
    }
  }

  var actionTitle: String {
    switch target {
    case .focus: "Adjust focus"
    case .reminder: "Adjust reminder"
    }
  }
}

/// Pure presentation policy, driven by the existing app clock rather than another timer.
struct NotchHeadsUpState {
  private(set) var active: NotchHeadsUp?
  private(set) var expiresAt: Date?
  private var presented: Set<NotchHeadsUp.Target> = []

  mutating func update(_ candidates: [NotchHeadsUp], at now: Date, holding: Bool = false) {
    presented.formIntersection(Set(candidates.map(\.target)))
    for candidate in candidates where candidate.deadline.timeIntervalSince(now) > 60 {
      presented.remove(candidate.target)
    }
    let upcoming = candidates.filter {
      $0.eligible && $0.deadline > now && $0.deadline.timeIntervalSince(now) <= 60
    }.sorted { $0.deadline < $1.deadline }
    if let current = active {
      if let refreshed = upcoming.first(where: { $0.target == current.target }),
        let expiresAt, holding || now < expiresAt
      {
        active = refreshed
        return
      }
      dismiss()
    }
    guard let next = upcoming.first(where: { !presented.contains($0.target) }) else { return }
    active = next
    expiresAt = now.addingTimeInterval(10)
    presented.insert(next.target)
  }

  mutating func dismiss() {
    active = nil
    expiresAt = nil
  }
}

/// The same minute choices work as inline actions or native context-menu items.
struct TimeAdjustmentChoices: View {
  var direction = 1
  var actionTitle = "Adjust time"
  var canApply: (Int) -> Bool = { _ in true }
  let action: (Int) -> Void

  var body: some View {
    ForEach([5, 10, 15], id: \.self) { minutes in
      Button("\(direction > 0 ? "+" : "−")\(minutes) Min") { action(minutes) }
        .disabled(!canApply(minutes))
        .help("\(direction > 0 ? "+" : "−")\(minutes) minutes")
        .accessibilityLabel("\(actionTitle) by \(minutes) minutes")
    }
  }
}

struct NotchHeadsUpView: View {
  @Bindable var store: AppStore
  let headsUp: NotchHeadsUp
  let dismiss: () -> Void

  var body: some View {
    VStack(spacing: 12) {
      Text(headsUp.title).font(IntervalTheme.heading).lineLimit(1)
      Text(durationString(max(0, headsUp.deadline.timeIntervalSince(store.now))))
        .font(.system(size: 28, weight: .medium, design: .rounded)).monospacedDigit()
        .foregroundStyle(.primary)
      HStack(spacing: 10) {
        TimeAdjustmentChoices(
          actionTitle: headsUp.actionTitle,
          canApply: { store.canAdjustHeadsUp(headsUp, minutes: $0) }
        ) {
          store.adjustHeadsUp(headsUp, minutes: $0)
          dismiss()
        }
      }.buttonStyle(IntervalOutlineButton()).controlSize(.regular)
    }.frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
