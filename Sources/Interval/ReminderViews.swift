import CoreGraphics
import IntervalCore
import SwiftUI

struct RemindersView: View {
  @Bindable var store: AppStore
  @State private var selection: UUID?
  @State private var deleting: Reminder?

  init(store: AppStore, selection: UUID? = nil, advanced: Bool = false) {
    self.store = store
    _selection = State(initialValue: selection)
    _ = advanced  // Retained for snapshot compatibility; all controls are now always visible.
  }

  var body: some View {
    GeometryReader { geometry in
      let isWide = geometry.size.width >= 650
      Group {
        if isWide {
          HStack(spacing: 0) {
            reminderList(showsEmptyTemplates: false).frame(width: 240)
            Divider()
            if let reminder = selectedReminder {
              editor(reminder, showsBackButton: false)
            } else {
              emptyTemplates
            }
          }
          .onAppear { selectInitialReminder() }
          .onChange(of: isWide) { _, wide in
            if wide { selectInitialReminder() }
          }
        } else if let reminder = selectedReminder {
          editor(reminder, showsBackButton: true)
        } else {
          reminderList(showsEmptyTemplates: true)
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity).background(GlassBackground())
    .navigationTitle("Reminders")
    .preferredColorScheme(.dark)
    .alert(
      "Delete \(deleting?.title ?? "reminder")?",
      isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
    ) {
      Button("Cancel", role: .cancel) { deleting = nil }
      Button("Delete", role: .destructive) {
        if let id = deleting?.id {
          let reminders = store.data.reminders
          let deletedIndex = reminders.firstIndex(where: { $0.id == id })
          store.deleteReminder(id)
          if let deletedIndex {
            let remaining = store.data.reminders
            selection =
              remaining.isEmpty ? nil : remaining[min(deletedIndex, remaining.count - 1)].id
          }
        }
        deleting = nil
      }
    } message: {
      Text("This reminder and its current schedule will be removed.")
    }
  }

  private var selectedReminder: Reminder? {
    guard let selection else { return nil }
    return store.data.reminders.first(where: { $0.id == selection })
  }

  private func reminderList(showsEmptyTemplates: Bool) -> some View {
    VStack(spacing: 0) {
      HStack {
        Text("Reminders").font(.system(size: 14, weight: .semibold)).foregroundStyle(.secondary)
        Spacer()
        addMenu
      }
      .padding(.horizontal, 12).padding(.vertical, 8)

      if store.data.reminders.isEmpty {
        if showsEmptyTemplates {
          emptyTemplates
        } else {
          Spacer()
        }
      } else {
        ScrollView {
          LazyVStack(spacing: 7) {
            ForEach(store.data.reminders) { reminder in
              reminderRow(reminder)
            }
          }
          .padding(.horizontal, 10).padding(.bottom, 10)
        }
      }
    }
  }

  private func editor(_ reminder: Reminder, showsBackButton: Bool) -> some View {
    VStack(spacing: 0) {
      HStack {
        if showsBackButton {
          Button {
            selection = nil
          } label: {
            Label("Back", systemImage: "chevron.left")
          }
          .buttonStyle(IntervalIconButton()).help("Back to reminders")
        }
        Text("Reminder").font(.system(size: 14, weight: .semibold))
        Spacer()
        Button {
          store.previewReminder(reminder.id)
        } label: {
          Label("Preview reminder", systemImage: "play.rectangle")
        }.buttonStyle(IntervalIconButton()).help("Preview reminder")
        Menu {
          Button("Delete Reminder…", role: .destructive) { deleting = reminder }
        } label: {
          Image(systemName: "ellipsis").font(.system(size: 17, weight: .medium)).frame(
            width: 36, height: 36)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .accessibilityLabel("Reminder actions")
      }
      .padding(.horizontal, 18).padding(.vertical, 8)
      ReminderEditor(reminder: reminder, store: store)
        .id(reminder.id)
    }
  }

  private func selectInitialReminder() {
    if selectedReminder == nil {
      selection = store.data.reminders.first?.id
    }
  }

  private func reminderRow(_ reminder: Reminder) -> some View {
    HStack(spacing: 11) {
      Button {
        selection = reminder.id
      } label: {
        HStack(spacing: 11) {
          Text(reminder.emoji).font(.title2).frame(width: 34, height: 34)
            .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
          VStack(alignment: .leading, spacing: 3) {
            Text(reminder.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
            Text(status(reminder)).font(.system(size: 14)).foregroundStyle(.secondary).lineLimit(1)
          }
          Spacer(minLength: 4)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel("\(reminder.title), \(status(reminder))")
      .accessibilityAddTraits(selection == reminder.id ? .isSelected : [])

      Toggle(
        "",
        isOn: Binding(
          get: { reminder.isEnabled },
          set: { enabled in
            var edited = reminder
            edited.isEnabled = enabled
            if enabled && edited.dueAt == nil {
              edited.dueAt = store.now.addingTimeInterval(edited.intervalSeconds)
            }
            store.updateReminder(edited)
          })
      )
      .labelsHidden().toggleStyle(SwitchToggleStyle(tint: .accentColor)).controlSize(.small)
      .accessibilityLabel("Enable \(reminder.title) reminder")
    }
    .padding(.vertical, 9).padding(.horizontal, 10)
    .background(
      selection == reminder.id ? IntervalTheme.accent.opacity(0.11) : Color.white.opacity(0.025),
      in: RoundedRectangle(cornerRadius: 11)
    )
  }

  private var addMenu: some View {
    Menu {
      Button("New Reminder") { selection = store.addReminder() }
      Divider()
      ForEach(Reminder.templates(startingAt: store.now)) { template in
        Button("\(template.emoji) \(template.title)") {
          selection = store.addReminder(template: template)
        }
      }
    } label: {
      Image(systemName: "plus").font(.system(size: 17, weight: .medium)).frame(
        width: 36, height: 36)
    }
    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
    .accessibilityLabel("Add reminder")
    .help("Add reminder or template")
  }

  private var emptyTemplates: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Templates").font(.system(size: 14)).foregroundStyle(.secondary)
      ForEach(Reminder.templates(startingAt: store.now)) { template in
        Button {
          selection = store.addReminder(template: template)
        } label: {
          HStack(spacing: 10) {
            Text(template.emoji).font(.title3)
            Text(template.title).font(.system(size: 14, weight: .medium))
            Spacer()
          }
          .padding(10).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      }
    }
    .padding(14).frame(maxHeight: .infinity, alignment: .top)
  }

  private func status(_ reminder: Reminder) -> String {
    guard reminder.isEnabled else { return "Off" }
    guard let due = reminder.effectiveDueAt else { return "Not scheduled" }
    let time = due.formatted(date: .omitted, time: .shortened)
    let day =
      Calendar.current.isDate(due, inSameDayAs: store.now)
      ? "" : due.formatted(.dateTime.month(.abbreviated).day()) + " · "
    return (reminder.snoozedUntil == nil ? "" : "Extended · ") + day + time
  }
}

private struct ReminderEditor: View {
  let reminder: Reminder
  @Bindable var store: AppStore

  private func binding<T>(_ keyPath: WritableKeyPath<Reminder, T>) -> Binding<T> {
    Binding(
      get: {
        store.data.reminders.first(where: { $0.id == reminder.id })?[keyPath: keyPath]
          ?? reminder[keyPath: keyPath]
      },
      set: { value in
        var edited = store.data.reminders.first(where: { $0.id == reminder.id }) ?? reminder
        edited[keyPath: keyPath] = value
        store.updateReminder(edited)
      })
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        editorSection("Content") {
          TextField("Title", text: binding(\.title))
            .textFieldStyle(.plain)
            .padding(8)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityLabel("Reminder title")
          TextField("Message", text: binding(\.message), axis: .vertical)
            .textFieldStyle(.plain)
            .padding(8)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            .lineLimit(2...5)
            .accessibilityLabel("Reminder message")
          HStack {
            Text("Emoji")
            Spacer()
            TextField("Emoji", text: binding(\.emoji))
              .textFieldStyle(.plain)
              .padding(8)
              .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
              .frame(width: 90)
              .multilineTextAlignment(.trailing)
              .accessibilityLabel("Reminder emoji")
          }
        }

        editorSection("Schedule") {
          HStack {
            Text("Repeat")
            Spacer()
            Text("\(Int(binding(\.intervalSeconds).wrappedValue / 60)) min").monospacedDigit()
            Stepper(
              "Repeat interval in minutes",
              value: binding(\.intervalSeconds), in: 60...86_400, step: 60
            )
            .labelsHidden()
            .accessibilityValue("\(Int(binding(\.intervalSeconds).wrappedValue / 60)) minutes")
            Menu {
              ForEach([10, 20, 30, 60], id: \.self) { minutes in
                Button("\(minutes) minutes") {
                  binding(\.intervalSeconds).wrappedValue = TimeInterval(minutes * 60)
                }
              }
            } label: {
              Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 17, weight: .medium)).frame(width: 36, height: 36)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .accessibilityLabel("Interval presets")
            .help("Choose an interval preset")
          }
          toggleRow("Hide during focus", value: binding(\.suppressDuringFocus))
          toggleRow("Hide during calendar events", value: binding(\.suppressDuringCalendar))
            .help("Uses selected calendars")
        }

        editorSection("Display") {
          HStack {
            Text("Show as")
            Spacer()
            Picker("Presentation", selection: binding(\.presentation)) {
              ForEach(ReminderPresentation.allCases, id: \.self) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented).labelsHidden().fixedSize().frame(
              width: 190, alignment: .trailing)
          }
          HStack {
            Text("Display for")
            Spacer()
            Text("\(Int(binding(\.displaySeconds).wrappedValue)) sec").monospacedDigit()
            Stepper(
              "Display duration in seconds", value: binding(\.displaySeconds),
              in: binding(\.presentation).wrappedValue == .fullscreen ? 5...600 : 2...600
            )
            .labelsHidden()
          }
          HStack {
            Text("Emoji size")
            Spacer()
            Slider(value: binding(\.emojiSize), in: 32...180).frame(width: 130)
            Text("\(Int(binding(\.emojiSize).wrappedValue)) pt").monospacedDigit().frame(
              width: 48, alignment: .trailing)
          }
          if binding(\.presentation).wrappedValue == .floating {
            HStack {
              Text("Position")
              Spacer()
              Picker("Position", selection: binding(\.position)) {
                ForEach(ReminderPosition.allCases, id: \.self) { Text($0.title).tag($0) }
              }.labelsHidden().fixedSize().frame(width: 190, alignment: .trailing)
            }
          }
          HStack {
            Text("Sound")
            Spacer()
            Picker("Sound", selection: binding(\.sound)) {
              ForEach(ReminderSound.allCases, id: \.self) { Text($0.title).tag($0) }
            }.labelsHidden().fixedSize().frame(width: 190, alignment: .trailing)
          }
        }
      }
      .padding(18).frame(maxWidth: .infinity, alignment: .leading)
    }
    .font(.system(size: 14))
    .background(GlassBackground()).preferredColorScheme(.dark)
  }

  private func toggleRow(_ title: String, value: Binding<Bool>) -> some View {
    HStack {
      Text(title)
      Spacer()
      Toggle(title, isOn: value).labelsHidden()
        .toggleStyle(SwitchToggleStyle(tint: .accentColor)).controlSize(.small)
    }
  }

  private func editorSection<Content: View>(
    _ title: String, @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.secondary)
      content()
    }
  }
}

struct ReminderWarningView: View {
  let reminder: Reminder
  let overlay: ReminderOverlay
  private var warning: (remaining: Int, paused: Bool) {
    if case .warning(_, let value, let paused) = overlay { return (Int(ceil(value)), paused) }
    return (0, false)
  }

  var body: some View {
    TimelineView(.periodic(from: .now, by: 0.5)) { _ in
      HStack(spacing: 8) {
        Text(reminder.emoji).font(.system(size: 28)).frame(width: 36, height: 36)
        VStack(alignment: .leading, spacing: 3) {
          Text(reminder.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
          Text(warningStatus)
            .font(.system(size: 14)).foregroundStyle(.white.opacity(0.9)).monospacedDigit()
            .lineLimit(1)
        }
        Spacer(minLength: 0)
      }
      .foregroundStyle(.white)
      .padding(.horizontal, 10).padding(.vertical, 7)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
    .preferredColorScheme(.dark)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(reminder.title). \(warningStatus)")
  }

  private var warningStatus: String {
    if warning.paused { return keyboardRecentlyActive ? "Typing" : "Waiting" }
    return "In \(warning.remaining)s"
  }

  private var keyboardRecentlyActive: Bool {
    min(
      CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown),
      CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyUp)
    ) < 1.5
  }
}

struct ReminderTakeoverView: View {
  let reminder: Reminder
  let shownAt: Date
  let skip: () -> Void
  let extend: (TimeInterval) -> Void

  var body: some View {
    ZStack {
      if reminder.presentation == .fullscreen {
        Color(white: 0.18).opacity(0.97).ignoresSafeArea()
      }

      VStack(spacing: 16) {
        Text(reminder.emoji)
          .font(.system(size: min(180, max(32, reminder.emojiSize))))
          .lineLimit(1)
        ScrollView {
          VStack(spacing: 10) {
            Text(reminder.title).font(.system(size: 34, weight: .semibold))
              .multilineTextAlignment(.center)
            Text(reminder.message).font(.system(size: 18)).foregroundStyle(.white.opacity(0.82))
              .multilineTextAlignment(.center).frame(maxWidth: 640)
          }
          .frame(maxWidth: .infinity)
        }
        .frame(minHeight: 100, maxHeight: 260)
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
          let remaining = max(0, 5 - Int(context.date.timeIntervalSince(shownAt)))
          HStack(spacing: 14) {
            Menu("Extend") {
              ForEach([5, 10, 15], id: \.self) { minutes in
                Button("\(minutes) minutes") { extend(TimeInterval(minutes * 60)) }
              }
            }
            .buttonStyle(.bordered)
            Button(remaining > 0 ? "Skip in \(remaining)s" : "Skip", action: skip)
              .buttonStyle(.borderedProminent)
              .disabled(remaining > 0)
          }
        }
        .font(.system(size: 14, weight: .semibold))
      }
      .padding(28)
      .frame(maxWidth: 720)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .preferredColorScheme(.dark)
  }
}
