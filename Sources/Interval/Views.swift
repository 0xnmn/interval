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
                if store.timer.kind == .focus {
                    Text("Cycle \(store.data.completedFocusCount % max(1, store.data.settings.longBreakEvery) + 1) of \(max(1, store.data.settings.longBreakEvery))")
                        .font(.callout).foregroundStyle(.secondary)
                }
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
                if let id = store.completionSessionID { ReflectionView(store: store, sessionID: id).padding(.bottom, 8) }
                if let notice = store.inAppNotification { Label(notice, systemImage: "bell.fill").foregroundStyle(.teal) }
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
                if let error = store.audioError { Label(error, systemImage: "speaker.slash").font(.caption).foregroundStyle(.orange) }
            }.padding(28).frame(maxWidth: 680, maxHeight: .infinity)
        }.background(Color(nsColor: .windowBackgroundColor))
            .alert("Abandon this interval?", isPresented: $confirmingAbandon) {
                Button("Keep Going", role: .cancel) {}
                Button("Abandon", role: .destructive, action: store.abandon)
            } message: { Text("Elapsed active time will be kept in History.") }
    }
    private var primaryTitle: String {
        switch store.timer.status {
        case .running: "Pause"
        case .paused: "Resume"
        default: store.timer.kind == .focus ? "Start Focus" : "Start Break"
        }
    }
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
    @State private var month = Date()
    @State private var selectedDay = Date()
    @State private var selectedSession: UUID?
    private var calendar: Calendar { .autoupdatingCurrent }
    init(store: AppStore) {
        self.store = store
        _month = State(initialValue: store.now)
        _selectedDay = State(initialValue: store.now)
    }
    var body: some View {
        HSplitView {
            VStack(spacing: 12) {
                HStack {
                    Button(action: { changeMonth(by: -1) }) { Image(systemName: "chevron.left") }.accessibilityLabel("Previous month")
                    Spacer()
                    Text(month.formatted(.dateTime.month(.wide).year())).font(.headline)
                    Spacer()
                    Button(action: { changeMonth(by: 1) }) { Image(systemName: "chevron.right") }.accessibilityLabel("Next month")
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
                    ForEach(CalendarDates.weekdaySymbols(calendar: calendar), id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                    ForEach(Array(CalendarDates.monthGrid(containing: month, calendar: calendar).enumerated()), id: \.offset) { _, date in
                        if let date {
                            let count = sessionCount(on: date)
                            Button("\(calendar.component(.day, from: date))") { selectedDay = date; selectedSession = nil }
                                .buttonStyle(.plain).frame(maxWidth: .infinity, minHeight: 28)
                                .background(calendar.isDate(date, inSameDayAs: selectedDay) ? Color.teal.opacity(0.22) : .clear, in: Circle())
                                .overlay(alignment: .bottom) { if count > 0 { Circle().fill(.teal).frame(width: 4, height: 4) } }
                                .accessibilityLabel("\(date.formatted(date: .complete, time: .omitted)), \(count) session\(count == 1 ? "" : "s")")
                                .accessibilityAddTraits(calendar.isDate(date, inSameDayAs: selectedDay) ? .isSelected : [])
                        } else { Color.clear.frame(height: 28) }
                    }
                }
                Divider()
                if daySessions.isEmpty {
                    ContentUnavailableView("No sessions this day", systemImage: "calendar")
                } else {
                    ScrollView { LazyVStack(alignment: .leading, spacing: 4) { ForEach(daySessions) { session in Button { selectedSession = session.id } label: { SessionRow(session: session).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 8).background(selectedSession == session.id ? Color.teal.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 7)) }.buttonStyle(.plain) } } }
                }
            }.padding().frame(minWidth: 390)
            if let id = selectedSession, let session = store.data.sessions.first(where: { $0.id == id }) { SessionInspector(store: store, session: session).frame(minWidth: 260) }
            else { ContentUnavailableView("Select a session", systemImage: "rectangle.and.pencil.and.ellipsis") }
        }.navigationTitle("History")
    }
    private var daySessions: [SessionRecord] {
        store.data.sessions.filter { calendar.isDate($0.endedAt, inSameDayAs: selectedDay) }.sorted { $0.endedAt < $1.endedAt }
    }
    private func sessionCount(on date: Date) -> Int { store.data.sessions.count { calendar.isDate($0.endedAt, inSameDayAs: date) } }
    private func changeMonth(by value: Int) {
        guard let newMonth = calendar.date(byAdding: .month, value: value, to: month),
              let interval = calendar.dateInterval(of: .month, for: newMonth),
              let range = calendar.range(of: .day, in: .month, for: newMonth) else { return }
        let day = min(calendar.component(.day, from: selectedDay), range.count)
        month = newMonth
        selectedDay = calendar.date(byAdding: .day, value: day - 1, to: interval.start) ?? interval.start
        selectedSession = nil
    }
}

struct SessionRow: View { let session: SessionRecord; var body: some View { HStack { Image(systemName: session.outcome == .completed ? "checkmark.circle.fill" : "xmark.circle").foregroundStyle(session.outcome == .completed ? .teal : .secondary); VStack(alignment: .leading) { Text(session.kind.title).font(.headline); Text("\(session.endedAt.formatted(date: .omitted, time: .shortened)) · \(durationString(session.activeDuration)) · \(session.outcome.rawValue.capitalized)").font(.caption).foregroundStyle(.secondary); if let feedback = session.feedback { Text(feedback.capitalized).font(.caption) } } }.padding(.vertical, 3) } }

struct ReflectionView: View {
    @Bindable var store: AppStore; let sessionID: UUID
    private var session: SessionRecord? { store.data.sessions.first { $0.id == sessionID } }
    private var feedback: Binding<SessionFeedback?> {
        Binding(get: { session?.feedback.flatMap(SessionFeedback.init(rawValue:)) },
                set: { store.updateSession(id: sessionID, feedback: $0, journal: session?.journal ?? "") })
    }
    private var journal: Binding<String> {
        Binding(get: { session?.journal ?? "" },
                set: { store.updateSession(id: sessionID, feedback: feedback.wrappedValue, journal: $0) })
    }
    var body: some View {
        GroupBox { VStack(alignment: .leading, spacing: 10) {
            Label("Focus complete — how did it feel?", systemImage: "sparkles").font(.title3.bold())
            HStack { ForEach(SessionFeedback.allCases, id: \.self) { value in
                let selected = feedback.wrappedValue == value
                Button { setFeedback(value) } label: { Label(value.title, systemImage: selected ? "checkmark.circle.fill" : "circle") }
                    .buttonStyle(.bordered)
                    .tint(selected ? .teal : .secondary)
                    .accessibilityAddTraits(feedback.wrappedValue == value ? .isSelected : [])
            } }
            TextField("Optional reflection", text: journal)
            HStack {
                Text("Your session is already saved. Your suggested break is ready.").font(.caption).foregroundStyle(.secondary)
                Spacer(); Button("Later", action: store.deferReflection); Button("Done", action: store.deferReflection).buttonStyle(.borderedProminent)
            }
        } }
    }
    private func setFeedback(_ value: SessionFeedback) { feedback.wrappedValue = value }
}

struct SessionInspector: View {
    @Bindable var store: AppStore; let session: SessionRecord
    var body: some View { Form { Section("Session") { LabeledContent("Started", value: session.startedAt.formatted()); LabeledContent("Active", value: durationString(session.activeDuration)); LabeledContent("Outcome", value: session.outcome.rawValue.capitalized) }; Section("Reflection") { Picker("Focus", selection: Binding<SessionFeedback?>(get: { session.feedback.flatMap(SessionFeedback.init(rawValue:)) }, set: { store.updateSession(id: session.id, feedback: $0, journal: session.journal ?? "") })) { Text("Pending").tag(SessionFeedback?.none); ForEach(SessionFeedback.allCases, id: \.self) { Text($0.title).tag(Optional($0)) } }; TextEditor(text: Binding(get: { session.journal ?? "" }, set: { store.updateSession(id: session.id, feedback: session.feedback.flatMap(SessionFeedback.init(rawValue:)), journal: $0) })).frame(minHeight: 120) } }.formStyle(.grouped).padding() }
}

struct PlaceholderView: View {
    let title: String; let icon: String; let message: String
    var body: some View { ContentUnavailableView(title, systemImage: icon, description: Text(message)).navigationTitle(title) }
}

struct MenuBarView: View {
    @Bindable var store: AppStore
    @Environment(\.openWindow) private var openWindow
    @State private var confirmingAbandon = false
    @State private var quickNote = ""
    var body: some View {
        VStack(spacing: 14) {
            Text(store.timer.kind.title).font(.headline)
            Text(durationString(store.remaining)).font(.system(size: 38, weight: .semibold, design: .rounded)).monospacedDigit()
            if store.timer.kind == .focus { Text("Cycle \(store.data.completedFocusCount % max(1, store.data.settings.longBreakEvery) + 1) of \(max(1, store.data.settings.longBreakEvery))").font(.caption).foregroundStyle(.secondary) }
            HStack { Button(primaryTitle, action: store.startOrToggle).buttonStyle(.borderedProminent); if store.timer.status == .running || store.timer.status == .paused { Button("Abandon", role: .destructive) { confirmingAbandon = true } } }
            if store.completionSessionID != nil {
                Button("Open Reflection") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
            }
            Divider()
            HStack { TextField("Quick note", text: $quickNote).onSubmit { store.appendQuickNote(quickNote); quickNote = "" }; Button("Add") { store.appendQuickNote(quickNote); quickNote = "" }.disabled(quickNote.isEmpty) }
            HStack { Button("Open Interval") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }; SettingsLink { Text("Settings") }; Spacer(); Button("Quit") { NSApp.terminate(nil) } }
        }.padding(16).frame(width: 310).tint(.teal)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(store.timer.kind.title), \(store.timer.status.rawValue), \(spokenDuration(store.remaining)) remaining")
            .alert("Abandon this interval?", isPresented: $confirmingAbandon) {
                Button("Keep Going", role: .cancel) {}
                Button("Abandon", role: .destructive, action: store.abandon)
            } message: { Text("Elapsed active time will be kept in History.") }
    }
    private var primaryTitle: String { store.timer.status == .running ? "Pause" : store.timer.status == .paused ? "Resume" : store.timer.kind == .focus ? "Start Focus" : "Start Break" }
}

func durationString(_ seconds: TimeInterval) -> String {
    let total = max(0, Int(ceil(seconds))); return String(format: "%02d:%02d", total / 60, total % 60)
}

func spokenDuration(_ seconds: TimeInterval) -> String {
    let total = max(0, Int(ceil(seconds)))
    let minutes = total / 60, remainder = total % 60
    return "\(minutes) minute\(minutes == 1 ? "" : "s"), \(remainder) second\(remainder == 1 ? "" : "s")"
}
