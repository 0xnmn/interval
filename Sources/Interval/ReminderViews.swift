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
    HStack(spacing: 0) {
      VStack(spacing: 0) {
        HStack {
          VStack(alignment: .leading, spacing: 3) {
            Text("REMINDERS").font(.caption2.weight(.semibold)).tracking(1.4)
              .foregroundStyle(IntervalTheme.accent)
            Text("Your thoughtful interruptions").font(.headline)
          }
          Spacer()
          addMenu(compact: true)
        }
        .padding(16)

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

        Divider().overlay(Color.white.opacity(0.06))
        HStack {
          addMenu(compact: false)
          Spacer()
          if let selection,
            let reminder = store.data.reminders.first(where: { $0.id == selection })
          {
            Button("Delete", role: .destructive) { deleting = reminder }
              .buttonStyle(.plain).foregroundStyle(.red.opacity(0.85))
          }
        }
        .padding(12)
      }
      .frame(width: 300)
      .frame(maxHeight: .infinity, alignment: .top)
      .background(GlassBackground())
      Rectangle().fill(IntervalTheme.border).frame(width: 1)
      if let selection,
        let reminder = store.data.reminders.first(where: { $0.id == selection })
      {
        ReminderEditor(reminder: reminder, store: store, advanced: $advanced)
      } else if store.data.reminders.isEmpty {
        emptyDetail
      } else {
        ContentUnavailableView(
          "Choose a reminder", systemImage: "bell.badge",
          description: Text("Select one to shape when and how it appears."))
      }
    }
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
      .labelsHidden().toggleStyle(.switch).controlSize(.small)
      .accessibilityLabel("Enable \(reminder.title) reminder")
    }
    .padding(.vertical, 9).padding(.horizontal, 10)
    .background(
      selection == reminder.id ? IntervalTheme.accent.opacity(0.11) : Color.white.opacity(0.025),
      in: RoundedRectangle(cornerRadius: 11)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 11).stroke(
        selection == reminder.id ? IntervalTheme.accent.opacity(0.28) : IntervalTheme.border))
  }

  private func addMenu(compact: Bool) -> some View {
    Menu {
      Button("Blank Reminder") { selection = store.addReminder() }
      Divider()
      ForEach(Reminder.templates(startingAt: store.now)) { template in
        Button("\(template.emoji) \(template.title)") {
          selection = store.addReminder(template: template)
        }
      }
    } label: {
      if compact {
        Image(systemName: "plus").frame(width: 24, height: 24)
      } else {
        Label("Add reminder", systemImage: "plus")
      }
    }
    .menuStyle(.borderlessButton).fixedSize()
    .accessibilityLabel("Add reminder")
  }

  private var emptyTemplates: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("START WITH AN INTENTION").font(.caption2.weight(.semibold)).tracking(1.1)
        .foregroundStyle(.secondary)
      ForEach(Reminder.templates(startingAt: store.now)) { template in
        Button {
          selection = store.addReminder(template: template)
        } label: {
          HStack(spacing: 10) {
            Text(template.emoji).font(.title3)
            VStack(alignment: .leading, spacing: 2) {
              Text(template.title).font(.subheadline.weight(.medium))
              Text(template.message).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.tertiary)
          }
          .padding(10).contentShape(Rectangle())
        }
        .buttonStyle(.plain).intervalPanel()
      }
    }
    .padding(14).frame(maxHeight: .infinity, alignment: .top)
  }

  private var emptyDetail: some View {
    VStack(spacing: 12) {
      Image(systemName: "bell.badge").font(.system(size: 30)).foregroundStyle(IntervalTheme.accent)
      Text("Make space for what matters").font(.title2.weight(.semibold))
      Text("Choose a gentle starting point on the left, or create a blank reminder.")
        .foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 380)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity).background(GlassBackground())
  }

  private func status(_ reminder: Reminder) -> String {
    guard reminder.isEnabled else { return "Off" }
    guard let due = reminder.effectiveDueAt else { return "Not scheduled" }
    return (reminder.snoozedUntil == nil ? "Next " : "Snoozed until ")
      + due.formatted(date: .abbreviated, time: .shortened)
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
      VStack(alignment: .leading, spacing: 18) {
        HStack(alignment: .top) {
          VStack(alignment: .leading, spacing: 3) {
            Text("REMINDER DESIGN").font(.caption2.weight(.semibold)).tracking(1.4)
              .foregroundStyle(IntervalTheme.accent)
            Text(binding(\.title).wrappedValue).font(.title2.weight(.semibold)).lineLimit(1)
          }
          Spacer()
          Button("Preview") { store.previewReminder(reminder.id) }
            .buttonStyle(IntervalPrimaryButton())
        }

        preview

        editorSection("MESSAGE", systemImage: "text.alignleft") {
          TextField("Title", text: binding(\.title))
          TextField("Message", text: binding(\.message), axis: .vertical).lineLimit(2...5)
          HStack {
            Text("Emoji").foregroundStyle(.secondary)
            Spacer()
            TextField("Emoji", text: binding(\.emoji)).frame(width: 90)
              .multilineTextAlignment(.trailing)
          }
        }

        editorSection("TIMING & APPEARANCE", systemImage: "clock") {
          Stepper(
            "Every \(Int(binding(\.intervalSeconds).wrappedValue / 60)) minutes",
            value: binding(\.intervalSeconds), in: 60...86_400, step: 60)
          Picker("Presentation", selection: binding(\.presentation)) {
            ForEach(ReminderPresentation.allCases, id: \.self) { Text($0.title).tag($0) }
          }
          .pickerStyle(.segmented)
        }

        DisclosureGroup(isExpanded: $advanced) {
          VStack(spacing: 14) {
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
            Toggle("Suppress during focus or paused focus", isOn: binding(\.suppressDuringFocus))
            Toggle(
              "Suppress during selected calendar events", isOn: binding(\.suppressDuringCalendar))
          }
          .padding(.top, 8)
        } label: {
          Label("Advanced behavior", systemImage: "slider.horizontal.3")
            .font(.subheadline.weight(.semibold))
        }
        .padding(16).intervalPanel()

        Text("Changes save automatically.").font(.caption).foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .trailing)
      }
      .padding(24).frame(maxWidth: 720)
    }
    .frame(minWidth: 410).background(GlassBackground()).preferredColorScheme(.dark)
  }

  private var preview: some View {
    HStack(spacing: 16) {
      Text(binding(\.emoji).wrappedValue).font(.system(size: 38)).frame(width: 58, height: 58)
        .background(IntervalTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
      VStack(alignment: .leading, spacing: 5) {
        Text(binding(\.title).wrappedValue).font(.headline).lineLimit(1)
        Text(binding(\.message).wrappedValue).font(.subheadline).foregroundStyle(.secondary)
          .lineLimit(2)
      }
      Spacer()
    }
    .padding(18).intervalPanel()
  }

  private func editorSection<Content: View>(
    _ title: String, systemImage: String, @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      Label(title, systemImage: systemImage).font(.caption.weight(.semibold)).tracking(0.8)
        .foregroundStyle(.secondary)
      content()
    }
    .padding(16).intervalPanel()
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
    HStack(spacing: 12) {
      Text(reminder.emoji).font(.system(size: 30)).frame(width: 42, height: 42)
        .background(IntervalTheme.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 11))
      VStack(alignment: .leading, spacing: 3) {
        Text(reminder.title).font(.subheadline.weight(.semibold)).lineLimit(1)
        Text(
          warning.paused
            ? "Paused — \(warning.remaining)s idle time remaining"
            : "Ready in \(warning.remaining)s of idle time"
        )
        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
      }
      Spacer(minLength: 0)
    }
    .padding(14).frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(GlassBackground())
    .clipShape(RoundedRectangle(cornerRadius: 16))
    .overlay(RoundedRectangle(cornerRadius: 16).stroke(IntervalTheme.border))
    .preferredColorScheme(.dark)
    .accessibilityElement(children: .combine)
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
          Button("Remind me in 5 min", action: snooze).buttonStyle(.bordered)
          Button("Dismiss", action: dismiss).buttonStyle(.bordered)
            .tint(IntervalTheme.accent).keyboardShortcut(.cancelAction)
        }
        .font(.subheadline.weight(.medium))
        Text("Closes after \(Int(reminder.displaySeconds)) seconds. Escape dismisses it.")
          .font(.caption2).foregroundStyle(.secondary).padding(.top, 12)
      }
      .padding(34)
    }
    .preferredColorScheme(.dark)
  }
}
