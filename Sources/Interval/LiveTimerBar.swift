import IntervalCore
import SwiftUI

struct LiveTimerBar: View {
  @Bindable var store: AppStore
  @State private var confirmingBreak = false
  @State private var confirmingAbandon = false

  private var accent: Color {
    (store.completionSessionID != nil || store.timer.kind == .focus
      ? store.data.settings.focusColor : store.data.settings.breakColor).color
  }

  private var title: String {
    if store.completionSessionID != nil { return "Focus complete" }
    let value = store.timer.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return value.isEmpty ? store.timer.kind.title : value
  }

  var body: some View {
    HStack(spacing: 12) {
      Button {
        store.showFocus()
      } label: {
        HStack(spacing: 10) {
          Image(systemName: store.timer.kind == .focus ? "timer" : "cup.and.saucer")
            .font(.system(size: 17, weight: .medium)).foregroundStyle(accent)
          VStack(alignment: .leading, spacing: 3) {
            Text(title)
              .font(.callout.weight(.medium)).lineLimit(1)
            Text(
              store.completionSessionID != nil
                ? "Ready for reflection"
                : "\(store.timer.status == .running ? "Live" : "Ready") · \(store.timer.categoryName ?? "Uncategorized") · \(store.timer.kind.title)"
            )
            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
          }
        }
      }.buttonStyle(.plain).help("Open focus timer")
      Spacer(minLength: 12)
      if store.completionSessionID != nil {
        Button {
          store.showFocus()
        } label: {
          Label("Review focus", systemImage: "square.and.pencil")
        }
        .help("Review completed focus")
      } else {
        Text(durationString(store.remaining)).font(.title2.weight(.medium)).monospacedDigit()
          .foregroundStyle(accent).fixedSize()
          .accessibilityLabel("Live \(store.timer.kind.title) timer")
          .accessibilityValue(spokenDuration(store.remaining))
        if store.timer.status == .ready {
          Button(action: store.startSession) { Label("Start", systemImage: "play.fill") }
            .foregroundStyle(accent).help("Start interval")
        } else if store.timer.status == .running {
          if store.timer.kind == .focus {
            Button {
              confirmingBreak = true
            } label: {
              Label("Break", systemImage: "cup.and.saucer")
            }
            .foregroundStyle(store.data.settings.breakColor.color).help("Start a break")
          } else {
            Button {
              store.endBreak()
            } label: {
              Label("End break", systemImage: "briefcase")
            }
            .foregroundStyle(store.data.settings.focusColor.color).help(
              "End break · Return to focus")
          }
          Button {
            confirmingAbandon = true
          } label: {
            Label("Abandon", systemImage: "stop")
          }
          .help("Abandon interval")
        }
      }
    }.buttonStyle(IntervalIconButton())
      .padding(.horizontal, 20).padding(.vertical, 12)
      .background(accent.opacity(0.07))
      .alert("Start a break now?", isPresented: $confirmingBreak) {
        Button("Keep Focusing", role: .cancel) {}
        Button("Start Break") { store.startBreakNow() }
      } message: {
        Text("This unfinished focus session will be saved as abandoned. Your focus time is kept.")
      }
      .alert("Abandon this interval?", isPresented: $confirmingAbandon) {
        Button("Keep Going", role: .cancel) {}
        Button("Abandon", role: .destructive, action: store.abandon)
      } message: {
        Text("Elapsed active time will be kept in Stats.")
      }
  }
}
