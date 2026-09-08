import CoreGraphics
import IntervalCore
import SwiftUI

struct RemindersView: View {
  @Bindable var store: AppStore
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
    .buttonStyle(.glass)
    .navigationTitle("Reminders")
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
        Text("Reminders").font(.title3.weight(.semibold))
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
        Text("Reminder").font(.title3.weight(.semibold))
        Spacer()
        Button {
          store.previewReminder(reminder.id)
        } label: {
          Label("Preview Reminder", systemImage: "eye")
        }.buttonStyle(IntervalIconButton()).help("Preview reminder")
        Menu {
          Button("Delete Reminder…", role: .destructive) { deleting = reminder }
        } label: {
          Image(systemName: "ellipsis").font(IntervalTheme.icon).frame(
            width: 36, height: 36)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .accessibilityLabel("Reminder actions")
      }
      .padding(.horizontal, 18).padding(.vertical, 8)
      ReminderEditor(reminder: reminder, store: store)
        .intervalEntrance()
        .id(reminder.id)
    }
  }

  private func selectInitialReminder() {
    if selectedReminder == nil {
      selection = store.data.reminders.first?.id
    }
  }

  private func reminderRow(_ reminder: Reminder) -> some View {
    let reminderName = meaningfulTitle(reminder.title)
    return HStack(spacing: 11) {
      Button {
        selection = reminder.id
      } label: {
        HStack(spacing: 11) {
          Text(reminder.emoji).font(.title2).frame(width: 34, height: 34)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
          VStack(alignment: .leading, spacing: 3) {
            Text(reminderName).font(.system(size: 14, weight: .semibold)).lineLimit(1)
            Text(status(reminder)).font(.system(size: 14)).foregroundStyle(.secondary).lineLimit(1)
          }
          Spacer(minLength: 4)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(IntervalSelectionButton(selected: selection == reminder.id))
      .accessibilityLabel("\(reminderName), \(status(reminder))")
      .accessibilityAddTraits(selection == reminder.id ? .isSelected : [])

      Toggle(
        reminderName,
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
      .accessibilityLabel(reminderName)
      .accessibilityValue(reminder.isEnabled ? "On" : "Off")
    }
    .padding(.vertical, 9).padding(.horizontal, 10)
    .animation(reduceMotion ? nil : IntervalMotion.selection, value: selection)
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
      Image(systemName: "plus").font(IntervalTheme.icon).frame(
        width: 36, height: 36)
    }
    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
    .accessibilityLabel("Add reminder")
    .help("Add reminder or template")
  }

  private var emptyTemplates: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("No reminders yet").font(.system(size: 17, weight: .semibold))
      Button {
        selection = store.addReminder()
      } label: {
        Label("New Reminder", systemImage: "plus")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.glassProminent)

      Text("Start from a template").font(.system(size: 14)).foregroundStyle(.secondary)
      ForEach(Reminder.templates(startingAt: store.now)) { template in
        Button {
          selection = store.addReminder(template: template)
        } label: {
          HStack(spacing: 10) {
            Text(template.emoji).font(.title3)
            Text(template.title).font(.system(size: 14, weight: .medium))
            Spacer()
            Image(systemName: "plus")
              .font(.system(size: 12, weight: .semibold))
              .foregroundStyle(.secondary)
          }
          .padding(12).contentShape(Rectangle())
        }
        .buttonStyle(IntervalSelectionButton())
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
    return day + time
  }

  private func meaningfulTitle(_ title: String) -> String {
    title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "New reminder" : title
  }
}

private struct ReminderEditor: View {
  let reminder: Reminder
  @Bindable var store: AppStore
  @State private var previewSound: NSSound?
  @State private var titleDraft: String
  @FocusState private var titleIsFocused: Bool

  init(reminder: Reminder, store: AppStore) {
    self.reminder = reminder
    self.store = store
    _titleDraft = State(initialValue: reminder.title)
  }

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
          VStack(alignment: .leading, spacing: 6) {
            Text("Title").foregroundStyle(.secondary)
            TextField("Reminder title", text: $titleDraft)
              .textFieldStyle(.plain)
              .padding(8)
              .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
              .accessibilityLabel("Reminder title")
              .focused($titleIsFocused)
              .onChange(of: titleDraft) { _, draft in
                guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                binding(\.title).wrappedValue = draft
              }
              .onChange(of: titleIsFocused) { _, focused in
                guard !focused else { return }
                if titleDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                  titleDraft = "New reminder"
                  binding(\.title).wrappedValue = titleDraft
                }
              }
            if titleDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
              Text("Enter a reminder title.")
                .font(.caption)
                .foregroundStyle(.red)
            }
          }
          VStack(alignment: .leading, spacing: 6) {
            Text("Message").foregroundStyle(.secondary)
            TextField("Optional message", text: binding(\.message), axis: .vertical)
              .textFieldStyle(.plain)
              .padding(8)
              .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
              .lineLimit(2...5)
              .accessibilityLabel("Reminder message")
          }
          HStack {
            Text("Emoji")
            Spacer()
            TextField("Emoji", text: binding(\.emoji))
              .textFieldStyle(.plain)
              .padding(8)
              .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
              .frame(width: 90)
              .multilineTextAlignment(.trailing)
              .accessibilityLabel("Reminder emoji")
          }
        }

        editorSection("Schedule") {
          HStack {
            Text("Every")
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
                Button("\(minutes) Minutes") {
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
          toggleRow("Skip during focus", value: binding(\.suppressDuringFocus))
            .help("Missed occurrences are not queued.")
          toggleRow("Skip during calendar events", value: binding(\.suppressDuringCalendar))
            .help("Uses selected calendars. Missed occurrences are not queued.")
          toggleRow("Pause when idle", value: binding(\.pauseWhenIdle))
            .help("Pause the repeat interval when there is no mouse or keyboard activity.")
          if binding(\.pauseWhenIdle).wrappedValue {
            HStack {
              Text("Idle delay")
              Spacer()
              Text("\(Int(binding(\.idleDelaySeconds).wrappedValue)) sec").monospacedDigit()
              Stepper(
                "Idle delay in seconds", value: binding(\.idleDelaySeconds), in: 1...3_600, step: 1
              )
              .labelsHidden()
              .accessibilityValue("\(Int(binding(\.idleDelaySeconds).wrappedValue)) seconds")
            }
            .help("Resume the interval as soon as you move the mouse or use the keyboard.")
          }
        }

        editorSection("Display") {
          Picker("Style", selection: binding(\.presentation)) {
            ForEach(ReminderPresentation.allCases, id: \.self) { Text($0.title).tag($0) }
          }
          Text(
            binding(\.presentation).wrappedValue == .overlay
              ? "A small, click-through reminder over your workspace. Closes automatically."
              : "Covers each display with its wallpaper."
          )
          .foregroundStyle(.secondary)
          if binding(\.presentation).wrappedValue == .fullscreen,
            Wallpaper.captureAvailability == .permissionRequired
          {
            Button("Allow Wallpaper Access…") {
              CGRequestScreenCaptureAccess()
              NSWorkspace.shared.open(
                URL(
                  string:
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
              )
            }.help(
              "Screen Recording access lets Interval read each display’s actual wallpaper, including dynamic wallpapers. Only the wallpaper window is captured."
            )
          }
          HStack {
            Text("Display for")
            Spacer()
            Text("\(Int(binding(\.displaySeconds).wrappedValue)) sec").monospacedDigit()
            Stepper(
              "Display duration in seconds", value: binding(\.displaySeconds),
              in: binding(\.presentation).wrappedValue.minimumDuration...600
            )
            .labelsHidden()
          }
          HStack {
            Text("Emoji size")
            Spacer()
            Slider(value: binding(\.emojiSize), in: 32...180).frame(width: 130)
              .accessibilityLabel("Emoji size")
            Text("\(Int(binding(\.emojiSize).wrappedValue)) pt").monospacedDigit().frame(
              width: 48, alignment: .trailing)
          }
          HStack {
            Text("Sound")
            Spacer()
            Picker("Sound", selection: binding(\.sound)) {
              ForEach(ReminderSound.allCases, id: \.self) { Text($0.title).tag($0) }
            }.labelsHidden().frame(width: 140)
            if binding(\.sound).wrappedValue != .none {
              Button {
                previewSound?.stop()
                // Named sounds are cached. Keep previews independent of a live reminder cue.
                let sound =
                  NSSound(named: NSSound.Name(binding(\.sound).wrappedValue.title))?.copy()
                  as? NSSound
                previewSound = sound
                sound?.play()
              } label: {
                Label("Preview Sound", systemImage: "speaker.wave.2")
              }.buttonStyle(IntervalIconButton())
                .help("Preview reminder sound")
            }
          }
        }
      }
      .padding(18)
      .frame(maxWidth: 520, alignment: .leading)
      .frame(maxWidth: .infinity, alignment: .center)
    }
    .font(.system(size: 14))
    .background(GlassBackground())
    .onDisappear { previewSound?.stop() }
    .onChange(of: binding(\.sound).wrappedValue) { _, _ in previewSound?.stop() }
    .onChange(of: store.reminderOverlay) { _, _ in previewSound?.stop() }
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
      Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.primary)
      content()
    }
  }
}

struct ReminderWarningView: View {
  static let size = NSSize(width: 250, height: 36)
  let reminder: Reminder
  let overlay: ReminderOverlay
  var audioInputActivity: AudioInputActivity? = nil
  private var warning: (remaining: Int, paused: Bool) {
    if case .warning(_, let value, let paused) = overlay { return (Int(ceil(value)), paused) }
    return (0, false)
  }

  var body: some View {
    TimelineView(.periodic(from: .now, by: 0.5)) { _ in
      HStack(spacing: 8) {
        Text(reminder.emoji).font(.system(size: 18)).frame(width: 22)
        Text(reminder.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
        Spacer(minLength: 4)
        Text(warningStatus)
          .font(.system(size: 12)).foregroundStyle(.secondary).monospacedDigit()
          .lineLimit(1).fixedSize()
      }
      .foregroundStyle(.primary)
      .padding(.horizontal, 10).padding(.vertical, 7)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(reminder.title). \(warningStatus)")
  }

  var warningStatus: String {
    if audioInputActivity?.isActive == true { return "Mic On" }
    if warning.paused { return keyboardRecentlyActive ? "Typing" : "Waiting" }
    return "\(warning.remaining)s"
  }

  private var keyboardRecentlyActive: Bool {
    min(
      CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown),
      CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyUp)
    ) < 1.5
  }
}

struct ReminderOverlayView: View {
  let reminder: Reminder
  let shownAt: Date

  var body: some View {
    VStack(spacing: 10) {
      Text(reminder.emoji).font(.system(size: min(reminder.emojiSize, 72)))
      Text(reminder.title).font(.title2.weight(.semibold)).lineLimit(1)
      if !reminder.message.isEmpty {
        Text(reminder.message).font(IntervalTheme.body).foregroundStyle(.secondary)
          .multilineTextAlignment(.center).lineLimit(3)
      }
      TimelineView(.periodic(from: .now, by: 1)) { context in
        Text(
          "\(max(0, Int(ceil(reminder.displaySeconds - context.date.timeIntervalSince(shownAt)))))s"
        )
        .font(IntervalTheme.body).monospacedDigit().foregroundStyle(.secondary)
      }
    }.padding(24).frame(width: 360)
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
      .accessibilityElement(children: .combine)
  }
}

struct ReminderTakeoverView: View {
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.colorSchemeContrast) private var contrast
  let reminder: Reminder
  let shownAt: Date
  let skip: () -> Void
  let extend: (TimeInterval) -> Void
  var wallpaper: NSImage? = nil
  var animatesEntrance = true
  var isPreview = false
  @State private var messageContentHeight: CGFloat = 0

  static func remainingSeconds(reminder: Reminder, shownAt: Date, now: Date) -> Int {
    max(0, Int(ceil(reminder.displaySeconds - now.timeIntervalSince(shownAt))))
  }

  var body: some View {
    ZStack {
      fullscreenBackground
      fullscreenContent
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var fullscreenBackground: some View {
    GeometryReader { geometry in
      ZStack {
        if let wallpaper, !reduceTransparency, contrast != .increased {
          Image(nsImage: wallpaper)
            .resizable()
            .scaledToFill()
            .frame(width: geometry.size.width, height: geometry.size.height)
        } else {
          LinearGradient(
            colors: [Color(white: 0.2), Color(white: 0.06)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
        }
        // Keep the wallpaper's hue, with extra contrast behind the text and controls.
        LinearGradient(
          stops: [
            .init(color: .black.opacity(0.55), location: 0),
            .init(color: .black.opacity(0.32), location: 0.2),
            .init(color: .black.opacity(0.56), location: 0.5),
            .init(color: .black.opacity(0.32), location: 0.8),
            .init(color: .black.opacity(0.55), location: 1),
          ], startPoint: .top, endPoint: .bottom)
      }
      .frame(width: geometry.size.width, height: geometry.size.height)
      .clipped()
    }
    .ignoresSafeArea()
  }

  private var fullscreenContent: some View {
    GeometryReader { geometry in
      let spacious = geometry.size.height >= 900
      VStack(spacing: 24) {
        if isPreview {
          Text("Preview")
            .font(.system(size: 14, weight: .semibold))
            .textCase(.uppercase)
            .tracking(1.2)
            .foregroundStyle(.white.opacity(0.8))
            .intervalEntrance(delay: 0.12, enabled: animatesEntrance)
        }
        TimelineView(
          .periodic(
            from: Calendar.current.dateInterval(of: .minute, for: Date())?.start ?? Date(), by: 60)
        ) { context in
          Label(context.date.formatted(date: .omitted, time: .shortened), systemImage: "clock")
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(.white).monospacedDigit()
        }.intervalEntrance(delay: 0.30, enabled: animatesEntrance)

        VStack(spacing: 28) {
          fullscreenReminderContent(
            spacious: spacious,
            availableHeight: max(260, geometry.size.height - (isPreview ? 350 : 310))
          )
          liveCountdown(size: spacious ? 80 : 64)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)

        TimelineView(.periodic(from: .now, by: 1)) { context in
          fullscreenActions(now: context.date)
        }.intervalEntrance(delay: 0.42, enabled: animatesEntrance)
      }
      .padding(.horizontal, 32)
      .padding(.top, spacious ? 64 : 40)
      .padding(.bottom, spacious ? 52 : 32)
    }
    .environment(\.colorScheme, .dark)
  }

  private func fullscreenReminderContent(spacious: Bool, availableHeight: CGFloat) -> some View {
    let emojiSize = min(spacious ? 180 : 80, max(32, reminder.emojiSize))
    let messageViewportHeight = max(
      70,
      min(spacious ? 260 : 120, availableHeight - emojiSize - (spacious ? 290 : 210))
    )
    return VStack(spacing: 20) {
      Text(reminder.emoji)
        .font(.system(size: emojiSize))
        .lineLimit(1)
      Text(reminder.title)
        .font(.system(size: spacious ? 48 : 36, weight: .semibold))
        .lineLimit(3).minimumScaleFactor(0.7).fixedSize(horizontal: false, vertical: true)
      if !reminder.message.isEmpty {
        ScrollView {
          Text(reminder.message)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .background {
              GeometryReader { messageGeometry in
                Color.clear.preference(
                  key: ReminderMessageHeightKey.self, value: messageGeometry.size.height)
              }
            }
        }
        .frame(height: messageViewportHeight)
        .clipped()
        .scrollIndicators(.visible)
        .accessibilityLabel("Reminder message")
        .font(.system(size: spacious ? 22 : 18))
        .lineSpacing(4)
        .foregroundStyle(.white)
        .onPreferenceChange(ReminderMessageHeightKey.self) { messageContentHeight = $0 }
        if messageContentHeight > messageViewportHeight + 1 {
          Text("Scroll to read")
            .font(.system(size: 12, weight: .medium))
            .accessibilityHidden(true)
        }
      }
    }
    .foregroundStyle(.white)
    .multilineTextAlignment(.center)
    .frame(maxWidth: 720)
    .intervalEntrance(delay: 0.18, enabled: animatesEntrance)
  }

  private func liveCountdown(size: CGFloat) -> some View {
    TimelineView(.periodic(from: .now, by: 1)) { context in
      countdown(size: size, now: context.date)
    }.intervalEntrance(delay: 0.30, enabled: animatesEntrance)
  }

  private func countdown(size: CGFloat, now: Date) -> some View {
    Text(
      duration(
        ReminderTakeoverView.remainingSeconds(
          reminder: reminder, shownAt: shownAt, now: now))
    )
    .font(.system(size: size, weight: .regular))
    .monospacedDigit()
    .lineLimit(1).minimumScaleFactor(0.7)
    .accessibilityLabel("Time remaining")
    .accessibilityValue(
      spokenDuration(
        TimeInterval(
          Self.remainingSeconds(
            reminder: reminder, shownAt: shownAt, now: now))))
  }

  private func fullscreenActions(now: Date) -> some View {
    let skipRemaining = max(0, Int(ceil(5 - now.timeIntervalSince(shownAt))))
    return VStack(spacing: 12) {
      if isPreview {
        Button(action: skip) {
          Label("Close Preview", systemImage: "xmark")
        }
        .buttonStyle(ReminderGlassButtonStyle())
      } else {
        HStack(spacing: 12) {
          Button {
            extend(60)
          } label: {
            Text("+1 Min")
          }.help("+1 minute")
            .accessibilityLabel("Add 1 minute to reminder")
          Button {
            extend(5 * 60)
          } label: {
            Text("+5 Min")
          }.help("+5 minutes")
            .accessibilityLabel("Add 5 minutes to reminder")
          Button(action: skip) {
            Label(
              skipRemaining > 0 ? "Skip available in \(skipRemaining)s" : "Skip",
              systemImage: "forward.end"
            )
          }
          .disabled(skipRemaining > 0)
        }
        .buttonStyle(ReminderGlassButtonStyle())

        Text("Press Esc twice to skip")
          .font(.system(size: 14))
          .foregroundStyle(.white)
          .opacity(skipRemaining == 0 ? 1 : 0)
          .accessibilityHidden(skipRemaining > 0)
      }
    }
    .foregroundStyle(.white)
  }

  private func duration(_ seconds: Int) -> String {
    String(format: "%02d:%02d", seconds / 60, seconds % 60)
  }
}

private struct ReminderMessageHeightKey: PreferenceKey {
  static let defaultValue: CGFloat = 0
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = max(value, nextValue())
  }
}

private struct ReminderGlassButtonStyle: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.colorSchemeContrast) private var contrast
  @State private var hovering = false

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 15, weight: .medium))
      .foregroundStyle(.white)
      .frame(minWidth: 80)
      .padding(.horizontal, 20).padding(.vertical, 12)
      .background(Color(white: 0.2).opacity(reduceTransparency ? 1 : 0), in: Capsule())
      .modifier(ReminderInteractiveGlass(opaque: reduceTransparency || contrast == .increased))
      .overlay(
        Capsule().fill(.white.opacity(configuration.isPressed ? 0.18 : hovering ? 0.1 : 0))
          .allowsHitTesting(false)
      )
      .overlay(Capsule().strokeBorder(.white.opacity(hovering ? 0.5 : 0.22)))
      .opacity(isEnabled ? 1 : 0.65)
      .contentShape(Capsule())
      .animation(reduceMotion ? nil : IntervalMotion.selection, value: hovering)
      .animation(reduceMotion ? nil : IntervalMotion.selection, value: configuration.isPressed)
      .onHover { hovering = $0 }
  }
}

private struct ReminderInteractiveGlass: ViewModifier {
  let opaque: Bool

  @ViewBuilder func body(content: Content) -> some View {
    if opaque {
      content.background(Color(white: 0.2), in: Capsule())
    } else {
      content.glassEffect(.regular.tint(.white.opacity(0.08)).interactive(), in: Capsule())
    }
  }
}
