import IntervalCore
import SwiftUI

struct RemindersView: View {
    @Bindable var store: AppStore
    @State private var selection: UUID?
    @State private var deleting: Reminder?
    @State private var advanced: Bool

    init(store: AppStore, selection: UUID? = nil, advanced: Bool = false) {
        self.store = store; _selection = State(initialValue: selection); _advanced = State(initialValue: advanced)
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach(store.data.reminders) { reminder in
                        HStack {
                            Text(reminder.emoji).font(.title2)
                            VStack(alignment: .leading) {
                                Text(reminder.title).font(.headline)
                                Text(status(reminder)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: Binding(get: { reminder.isEnabled }, set: { enabled in
                                var edited = reminder; edited.isEnabled = enabled
                                if enabled && edited.dueAt == nil { edited.dueAt = store.now.addingTimeInterval(edited.intervalSeconds) }
                                store.updateReminder(edited)
                            })).labelsHidden().accessibilityLabel("Enable \(reminder.title) reminder")
                        }.tag(reminder.id)
                    }
                }
                HStack {
                    Menu { 
                        Button("Blank Reminder") { selection = store.addReminder() }
                        Divider()
                        ForEach(Reminder.templates(startingAt: store.now)) { template in
                            Button("\(template.emoji) \(template.title)") { selection = store.addReminder(template: template) }
                        }
                    } label: { Label("Add from Template", systemImage: "plus") }
                    Spacer()
                    if let selection, let reminder = store.data.reminders.first(where: { $0.id == selection }) {
                        Button("Delete", role: .destructive) { deleting = reminder }
                    }
                }.padding(10)
            }.frame(minWidth: 300)
            if let selection, let reminder = store.data.reminders.first(where: { $0.id == selection }) {
                ReminderEditor(reminder: reminder, store: store, advanced: $advanced)
            } else if store.data.reminders.isEmpty {
                ContentUnavailableView("No reminders", systemImage: "bell", description: Text("Add a blank reminder or choose one of four customizable templates."))
            } else { ContentUnavailableView("Select a reminder", systemImage: "bell") }
        }.navigationTitle("Reminders")
            .alert("Delete \(deleting?.title ?? "reminder")?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                Button("Cancel", role: .cancel) { deleting = nil }
                Button("Delete", role: .destructive) { if let id = deleting?.id { store.deleteReminder(id); selection = nil }; deleting = nil }
            } message: { Text("This reminder and its current schedule will be removed.") }
    }
    private func status(_ reminder: Reminder) -> String {
        guard reminder.isEnabled else { return "Off" }
        guard let due = reminder.effectiveDueAt else { return "Not scheduled" }
        return (reminder.snoozedUntil == nil ? "Next " : "Snoozed until ") + due.formatted(date: .abbreviated, time: .shortened)
    }
}

private struct ReminderEditor: View {
    let reminder: Reminder
    @Bindable var store: AppStore
    @Binding var advanced: Bool
    private func binding<T>(_ keyPath: WritableKeyPath<Reminder, T>) -> Binding<T> {
        Binding(get: { store.data.reminders.first(where: { $0.id == reminder.id })?[keyPath: keyPath] ?? reminder[keyPath: keyPath] },
                set: { value in var edited = store.data.reminders.first(where: { $0.id == reminder.id }) ?? reminder; edited[keyPath: keyPath] = value; store.updateReminder(edited) })
    }
    var body: some View {
        Form {
            Section("Reminder") {
                TextField("Title", text: binding(\.title))
                TextField("Message", text: binding(\.message), axis: .vertical).lineLimit(2...5)
                TextField("Emoji", text: binding(\.emoji)).frame(maxWidth: 130)
                Stepper("Every \(Int(binding(\.intervalSeconds).wrappedValue / 60)) minutes", value: binding(\.intervalSeconds), in: 60...86_400, step: 60)
                Picker("Presentation", selection: binding(\.presentation)) { ForEach(ReminderPresentation.allCases, id: \.self) { Text($0.title).tag($0) } }
            }
            DisclosureGroup("Advanced", isExpanded: $advanced) {
                Stepper("Display for \(Int(binding(\.displaySeconds).wrappedValue)) seconds", value: binding(\.displaySeconds), in: 3...600)
                HStack {
                    Text("Emoji size")
                    Slider(value: binding(\.emojiSize), in: 32...180).accessibilityLabel("Emoji size")
                    Text("\(Int(binding(\.emojiSize).wrappedValue)) pt").monospacedDigit().frame(width: 48)
                }
                Toggle("Suppress during focus or paused focus", isOn: binding(\.suppressDuringFocus))
                Toggle("Suppress during selected calendar events", isOn: binding(\.suppressDuringCalendar))
            }
            Section {
                HStack { Button("Preview") { store.previewReminder(reminder.id) }; Spacer(); Text("Changes save automatically.").font(.caption).foregroundStyle(.secondary) }
            }
        }.formStyle(.grouped).padding().frame(minWidth: 390)
    }
}

struct ReminderWarningView: View {
    let reminder: Reminder; let overlay: ReminderOverlay
    private var warning: (remaining: Int, paused: Bool) {
        if case .warning(_, let value, let paused) = overlay { return (Int(ceil(value)), paused) }
        return (0, false)
    }
    var body: some View {
        HStack(spacing: 14) {
            Text(reminder.emoji).font(.system(size: 36)).frame(width: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text(reminder.title).font(.headline)
                Text(warning.paused ? "Paused — \(warning.remaining)s idle time remaining" : "Ready in \(warning.remaining)s of idle time")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }.padding(18).frame(maxWidth: .infinity, maxHeight: .infinity).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
            .accessibilityElement(children: .combine)
    }
}

struct ReminderTakeoverView: View {
    let reminder: Reminder; let dismiss: () -> Void; let snooze: () -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        VStack(spacing: 18) {
            Text(reminder.emoji).font(.system(size: min(180, max(32, reminder.emojiSize)))).lineLimit(1)
            ScrollView {
                VStack(spacing: 14) {
                    Text(reminder.title).font(.largeTitle.bold()).multilineTextAlignment(.center)
                    Text(reminder.message).font(.title2).multilineTextAlignment(.center).frame(maxWidth: 640)
                }.frame(maxWidth: .infinity)
            }
            HStack { Button("Postpone this time · 5min", action: snooze); Button("Dismiss", action: dismiss).buttonStyle(.borderedProminent).keyboardShortcut(.cancelAction) }
            Text("Closes after \(Int(reminder.displaySeconds)) seconds. Escape dismisses it.").font(.caption).foregroundStyle(.secondary)
        }.padding(40).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(reduceTransparency ? AnyShapeStyle(Color(nsColor: .windowBackgroundColor)) : AnyShapeStyle(.ultraThinMaterial))
    }
}
