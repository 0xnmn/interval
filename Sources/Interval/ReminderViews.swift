import IntervalCore
import SwiftUI

struct RemindersView: View {
  @Bindable var store: AppStore
  @State private var selection: UUID?
  @State private var deleting: Reminder?
  @State private var advanced: Bool

  init(store: AppStore, selection: UUID? = nil, advanced: Bool = false) {
    self.store = store
    _selection = State(initialValue: selection)
    _advanced = State(initialValue: advanced)
  }

  var body: some View {
    VStack(spacing: 0) {
      if let selection,
        let reminder = store.data.reminders.first(where: { $0.id == selection })
      {
        HStack {
          Button {
            self.selection = nil
          } label: {
            Label("Back", systemImage: "chevron.left")
          }
          .buttonStyle(.plain)
          Spacer()
          Menu {
            Button("Delete Reminder…", role: .destructive) { deleting = reminder }
          } label: {
            Image(systemName: "ellipsis").font(.system(size: 14)).frame(width: 26, height: 26)
          }
          .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
          .accessibilityLabel("Reminder actions")
        }.padding(16)
        ReminderEditor(reminder: reminder, store: store, advanced: $advanced)
      } else {
        HStack {
          Text("Reminders").font(.headline)
          Spacer()
          addMenu
        }
        .padding(14)

        if store.data.reminders.isEmpty {
          emptyTemplates
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
    }.frame(maxWidth: .infinity, maxHeight: .infinity).background(GlassBackground())
      .navigationTitle("Reminders")
      .preferredColorScheme(.dark)
      .alert(
        "Delete \(deleting?.title ?? "reminder")?",
        isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
      ) {
        Button("Cancel", role: .cancel) { deleting = nil }
        Button("Delete", role: .destructive) {
          if let id = deleting?.id {
            store.deleteReminder(id)
            selection = nil
          }
          deleting = nil
        }
      } message: {
        Text("This reminder and its current schedule will be removed.")
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
            Text(reminder.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
            Text(status(reminder)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
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
      .labelsHidden().toggleStyle(SwitchToggleStyle(tint: .blue)).controlSize(.small)
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
      Image(systemName: "plus").font(.system(size: 14)).frame(width: 26, height: 26)
    }
    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
    .accessibilityLabel("Add reminder")
    .help("Add reminder or template")
  }

  private var emptyTemplates: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Templates").font(.caption).foregroundStyle(.secondary)
      ForEach(Reminder.templates(startingAt: store.now)) { template in
        Button {
          selection = store.addReminder(template: template)
        } label: {
          HStack(spacing: 10) {
            Text(template.emoji).font(.title3)
            Text(template.title).font(.subheadline.weight(.medium))
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
    return (reminder.snoozedUntil == nil ? "" : "Snoozed · ") + day + time
  }
}

private struct ReminderEditor: View {
  let reminder: Reminder
  @Bindable var store: AppStore
  @Binding var advanced: Bool

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
      VStack(alignment: .leading, spacing: 12) {
        HStack(alignment: .top) {
          Text("Reminder").font(.headline)
          Spacer()
          Button("Preview") { store.previewReminder(reminder.id) }
            .buttonStyle(IntervalPrimaryButton())
        }

        editorSection("Content") {
          TextField("Title", text: binding(\.title))
          TextField("Message", text: binding(\.message), axis: .vertical).lineLimit(2...5)
          LabeledContent("Emoji") {
            TextField("Emoji", text: binding(\.emoji)).frame(width: 90)
              .multilineTextAlignment(.trailing)
          }
        }

        editorSection("Schedule") {
          Stepper(
            "Every \(Int(binding(\.intervalSeconds).wrappedValue / 60)) minutes",
            value: binding(\.intervalSeconds), in: 60...86_400, step: 60)
          Picker("Presentation", selection: binding(\.presentation)) {
            ForEach(ReminderPresentation.allCases, id: \.self) { Text($0.title).tag($0) }
          }
          .pickerStyle(.segmented)
        }

        DisclosureGroup(isExpanded: $advanced) {
          VStack(spacing: 10) {
            Divider()
            Stepper(
              "Display for \(Int(binding(\.displaySeconds).wrappedValue)) seconds",
              value: binding(\.displaySeconds), in: 3...600)
            HStack {
              Text("Emoji size")
              Slider(value: binding(\.emojiSize), in: 32...180).accessibilityLabel("Emoji size")
              Text("\(Int(binding(\.emojiSize).wrappedValue)) pt").monospacedDigit().frame(
                width: 48)
            }
            Toggle("Hide during focus", isOn: binding(\.suppressDuringFocus))
              .toggleStyle(SwitchToggleStyle(tint: .blue)).controlSize(.small)
            Toggle(
              "Hide during calendar events", isOn: binding(\.suppressDuringCalendar)
            )
            .toggleStyle(SwitchToggleStyle(tint: .blue)).controlSize(.small)
            .help("Uses selected calendars")
          }
          .padding(.top, 8)
        } label: {
          Label("Options", systemImage: "slider.horizontal.3")
            .font(.subheadline.weight(.semibold))
        }
        .padding(.vertical, 8)
      }
      .padding(16).frame(maxWidth: .infinity, alignment: .leading)
    }
    .background(GlassBackground()).preferredColorScheme(.dark)
  }

  private func editorSection<Content: View>(
    _ title: String, @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(title).font(.headline)
      content()
    }
    .padding(.vertical, 6)
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
    HStack(spacing: 8) {
      Text(reminder.emoji).font(.system(size: 28)).frame(width: 36, height: 36)
      VStack(alignment: .leading, spacing: 3) {
        Text(reminder.title).font(.subheadline.weight(.semibold)).lineLimit(1)
        Text(
          warning.paused
            ? "Paused · \(warning.remaining)s idle"
            : "In \(warning.remaining)s"
        )
        .font(.caption).foregroundStyle(.white.opacity(0.9)).monospacedDigit().lineLimit(1)
      }
      Spacer(minLength: 0)
    }
    .foregroundStyle(.white)
    .padding(6).frame(maxWidth: .infinity, maxHeight: .infinity)
    .shadow(color: .black.opacity(0.95), radius: 2, y: 1)
    .shadow(color: .black.opacity(0.7), radius: 5)
    .preferredColorScheme(.dark)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(
      "\(reminder.title). \(warning.paused ? "Paused, \(warning.remaining) seconds of idle time remaining" : "Ready in \(warning.remaining) seconds of idle time")"
    )
  }
}

struct ReminderTakeoverView: View {
  let reminder: Reminder
  let dismiss: () -> Void
  let snooze: () -> Void

  var body: some View {
    ZStack {
      GlassBackground()
      RoundedRectangle(cornerRadius: 28)
        .stroke(
          LinearGradient(
            colors: [IntervalTheme.accent.opacity(0.22), Color.white.opacity(0.035)],
            startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .padding(10)

      VStack(spacing: 0) {
        Spacer(minLength: 32)
        Text(reminder.emoji)
          .font(.system(size: min(180, max(32, reminder.emojiSize))))
          .lineLimit(1).padding(.bottom, 20)
        ScrollView {
          VStack(spacing: 13) {
            Text(reminder.title).font(.system(size: 34, weight: .semibold))
              .multilineTextAlignment(.center)
            Text(reminder.message).font(.title3).foregroundStyle(.secondary)
              .multilineTextAlignment(.center).frame(maxWidth: 640)
          }
          .frame(maxWidth: .infinity)
        }
        .frame(maxHeight: 260)
        Spacer(minLength: 28)

        HStack(spacing: 22) {
          Button("Snooze 5 min", action: snooze).buttonStyle(.bordered)
          Button("Dismiss", action: dismiss).buttonStyle(.bordered)
            .tint(IntervalTheme.accent).keyboardShortcut(.cancelAction)
        }
        .font(.subheadline.weight(.medium))
      }
      .padding(34)
    }
    .preferredColorScheme(.dark)
  }
}
