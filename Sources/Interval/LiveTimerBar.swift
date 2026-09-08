import IntervalCore
import SwiftUI

struct LiveTimerBar: View {
  @Bindable var store: AppStore
  @State private var confirmingBreak = false
  @State private var confirmingAbandon = false

  private var accent: Color { .accentColor }

  private var title: String {
    if store.breakEnded { return "Break ended" }
    if store.timer.kind != .focus {
      return store.timer.status == .ready ? "Break" : "Taking a break"
    }
    let value = store.timer.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return value.isEmpty ? store.timer.kind.title : value
  }

  var body: some View {
    HStack(spacing: 12) {
      Button {
        store.showFocus()
      } label: {
        HStack(spacing: 10) {
          Image(
            systemName: store.timer.kind == .focus
              ? "timer" : "figure.mind.and.body"
          )
          .font(.system(size: 17, weight: .medium)).foregroundStyle(.primary)
          HStack(spacing: 8) {
            Text(title)
              .font(IntervalTheme.heading).lineLimit(1)
            if store.timer.kind == .focus || store.timer.status == .ready {
              Text(store.timer.status == .ready ? "Ready" : "Focus")
                .font(IntervalTheme.body).foregroundStyle(.secondary).lineLimit(1)
                .fixedSize()
            }
          }
        }
      }.buttonStyle(.plain).help("Open focus timer")
      Spacer(minLength: 12)
      if store.completionSessionID != nil {
        Button {
          store.showFocus()
        } label: {
          Label("Reflect", systemImage: "square.and.pencil")
        }
        .buttonStyle(IntervalIconButton())
        .help("Review completed focus")
      }
      Group {
        Text(store.timerText).font(.title2.weight(.medium)).monospacedDigit()
          .foregroundStyle(accent).fixedSize()
          .accessibilityLabel(
            store.breakEnded
              ? "Time beyond scheduled break" : "Live \(store.timer.kind.title) timer"
          )
          .accessibilityValue(spokenDuration(store.displayedTime))
        if store.timer.status == .ready {
          if store.timer.kind == .focus {
            Button(action: store.startSession) { Text("Start Session") }
              .buttonStyle(IntervalPrimaryButton())
              .foregroundStyle(accent).help("Start session")
          } else {
            Button(action: store.startSession) {
              Text("Start Break")
            }.buttonStyle(IntervalPrimaryButton()).help("Start break · ⌘⇧S")
          }
        } else if store.timer.status == .running || store.breakEnded {
          if store.timer.kind == .focus {
            Button {
              confirmingBreak = true
            } label: {
              Label("Take a Break", systemImage: "figure.mind.and.body")
            }
            .buttonStyle(IntervalIconButton())
            .help("Start a break · ⌘⇧B")
          } else {
            Button {
              store.endBreak()
            } label: {
              Text("Resume Focus")
            }
            .buttonStyle(IntervalPrimaryButton())
            .help("Resume focus")
          }
          Button {
            confirmingAbandon = true
          } label: {
            Label("Abandon", systemImage: "stop")
          }
          .help(store.timer.kind == .focus ? "Abandon focus session · ⌘⇧X" : "Abandon break · ⌘⇧X")
        }
      }
    }.buttonStyle(IntervalIconButton())
      .padding(.horizontal, 20).padding(.vertical, 8)
      .background(accent.opacity(0.07))
      .alert("Start a break now?", isPresented: $confirmingBreak) {
        Button("Keep Focusing", role: .cancel) {}
        Button("Start Break") { store.startBreakNow() }
      } message: {
        Text("This unfinished focus session will be saved as abandoned. Your focus time is kept.")
      }
      .alert(store.abandonTitle, isPresented: $confirmingAbandon) {
        Button("Keep Going", role: .cancel) {}
        Button("Abandon", role: .destructive, action: store.abandon)
      } message: {
        Text("Elapsed time will remain in Stats.")
      }
  }
}
