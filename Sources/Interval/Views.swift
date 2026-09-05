import SwiftUI
import IntervalCore

enum Destination: String, CaseIterable, Identifiable {
    case focus = "Focus", history = "History", reminders = "Reminders"
    var id: Self { self }
    var icon: String { switch self { case .focus: "timer"; case .history: "clock.arrow.circlepath"; case .reminders: "checklist" } }
}

struct MainView: View {
    @Bindable var store: AppStore
    @State private var selection: Destination?

    init(store: AppStore, selection: Destination = .focus) {
        self.store = store
        _selection = State(initialValue: selection)
    }

    var body: some View {
        NavigationSplitView {
            List(Destination.allCases, selection: $selection) { item in Label(item.rawValue, systemImage: item.icon).tag(item) }
                .navigationTitle("Interval")
        } detail: {
            switch selection ?? .focus {
            case .focus: FocusView(store: store)
            case .history: HistoryView(store: store)
            case .reminders: PlaceholderView(title: "Reminders", icon: "checklist", message: "Calendar-aware reminders arrive in a later phase.")
            }
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 205)
        .frame(minWidth: 780, minHeight: 540)
        .tint(.teal)
    }
}

struct FocusView: View {
    @Bindable var store: AppStore
    @State private var confirmingAbandon = false
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 18) {
                Picker("Interval type", selection: Binding(get: { store.timer.kind }, set: store.choose)) {
                    ForEach(TimerKind.allCases, id: \.self) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented).frame(maxWidth: 390).disabled(store.timer.status != .ready)
                Text(store.timer.kind.title.uppercased()).font(.caption.weight(.semibold)).tracking(1.8).foregroundStyle(.secondary)
                Text(durationString(store.remaining)).font(.system(size: 76, weight: .semibold, design: .rounded)).monospacedDigit()
                    .contentTransition(.numericText()).accessibilityLabel(timerAccessibilityLabel)
                HStack(spacing: 12) {
                    Button(action: store.startOrToggle) { Label(primaryTitle, systemImage: primaryIcon).frame(minWidth: 105) }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                    if store.timer.status == .running || store.timer.status == .paused {
                        Button("Abandon", role: .destructive) { confirmingAbandon = true }.buttonStyle(.bordered).controlSize(.large)
                    }
                }
                Text(statusText).font(.callout).foregroundStyle(.secondary)
            }.padding(.top, 48).padding(.horizontal, 42)
            Divider().padding(.top, 38)
            VStack(alignment: .leading, spacing: 10) {
                Label("Scratchpad", systemImage: "square.and.pencil").font(.headline)
                TextEditor(text: Binding(get: { store.data.scratchpad }, set: store.updateScratchpad))
                    .font(.body).scrollContentBackground(.hidden).padding(10)
                    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 9))
                    .accessibilityLabel("Global scratchpad")
                if let error = store.persistenceError {
                    Label(error, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.red)
                } else if store.didSave {
                    Label("Saved", systemImage: "checkmark.circle").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Changes save automatically.").font(.caption).foregroundStyle(.secondary)
                }
                if let recovery = store.recoveryMessage {
                    Label(recovery, systemImage: "pause.circle").font(.caption).foregroundStyle(.secondary)
                }
            }.padding(28).frame(maxWidth: 680, maxHeight: .infinity)
        }.background(Color(nsColor: .windowBackgroundColor))
            .alert("Abandon this interval?", isPresented: $confirmingAbandon) {
                Button("Keep Going", role: .cancel) {}
                Button("Abandon", role: .destructive, action: store.abandon)
            } message: { Text("Elapsed active time will be kept in History.") }
    }
    private var primaryTitle: String { switch store.timer.status { case .running: "Pause"; case .paused: "Resume"; default: "Start" } }
    private var primaryIcon: String { store.timer.status == .running ? "pause.fill" : "play.fill" }
    private var statusText: String {
        switch store.timer.status {
        case .ready: store.timer.kind == .focus ? "Ready when you are." : "Your focus is complete. Take a break when ready."
        case .running: "Stay with the interval."
        case .paused: "Paused — your place is saved."
        case .completed: "Complete"
        case .abandoned: "Abandoned"
        }
    }
    private var timerAccessibilityLabel: String {
        "\(store.timer.kind.title), \(store.timer.status.rawValue), \(spokenDuration(store.remaining)) remaining"
    }
}

struct HistoryView: View {
    @Bindable var store: AppStore
    var body: some View {
        Group {
            if store.data.sessions.isEmpty { PlaceholderView(title: "History", icon: "clock.arrow.circlepath", message: "Completed and abandoned intervals will appear here.") }
            else { List(store.data.sessions.reversed()) { session in
                HStack { Image(systemName: session.outcome == .completed ? "checkmark.circle.fill" : "xmark.circle").foregroundStyle(session.outcome == .completed ? .teal : .secondary)
                    VStack(alignment: .leading) { Text(session.kind.title).font(.headline); Text(session.endedAt.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.secondary) }
                    Spacer(); Text(session.outcome.rawValue.capitalized).foregroundStyle(.secondary)
                }.padding(.vertical, 5)
            }.navigationTitle("History") }
        }
    }
}

struct PlaceholderView: View {
    let title: String; let icon: String; let message: String
    var body: some View { ContentUnavailableView(title, systemImage: icon, description: Text(message)).navigationTitle(title) }
}

struct MenuBarView: View {
    @Bindable var store: AppStore
    @Environment(\.openWindow) private var openWindow
    @State private var confirmingAbandon = false
    var body: some View {
        VStack(spacing: 14) {
            Text(store.timer.kind.title).font(.headline)
            Text(durationString(store.remaining)).font(.system(size: 38, weight: .semibold, design: .rounded)).monospacedDigit()
            HStack { Button(primaryTitle, action: store.startOrToggle).buttonStyle(.borderedProminent); if store.timer.status == .running || store.timer.status == .paused { Button("Abandon", role: .destructive) { confirmingAbandon = true } } }
            Divider()
            HStack { Button("Open Interval") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }; SettingsLink { Text("Settings") }; Spacer(); Button("Quit") { NSApp.terminate(nil) } }
        }.padding(16).frame(width: 310).tint(.teal)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(store.timer.kind.title), \(store.timer.status.rawValue), \(spokenDuration(store.remaining)) remaining")
            .alert("Abandon this interval?", isPresented: $confirmingAbandon) {
                Button("Keep Going", role: .cancel) {}
                Button("Abandon", role: .destructive, action: store.abandon)
            } message: { Text("Elapsed active time will be kept in History.") }
    }
    private var primaryTitle: String { store.timer.status == .running ? "Pause" : store.timer.status == .paused ? "Resume" : "Start" }
}

func durationString(_ seconds: TimeInterval) -> String {
    let total = max(0, Int(ceil(seconds))); return String(format: "%02d:%02d", total / 60, total % 60)
}

func spokenDuration(_ seconds: TimeInterval) -> String {
    let total = max(0, Int(ceil(seconds)))
    let minutes = total / 60, remainder = total % 60
    return "\(minutes) minute\(minutes == 1 ? "" : "s"), \(remainder) second\(remainder == 1 ? "" : "s")"
}
