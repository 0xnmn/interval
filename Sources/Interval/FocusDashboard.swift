import IntervalCore
import SwiftUI

struct FocusControls: View {
  @Bindable var store: AppStore
  @State private var confirmingAbandon = false
  @State private var confirmingBreak = false
  @State private var adjustmentDirection: Int?
  private var active: Bool { store.timer.status == .running }
  private var accent: Color {
    (store.timer.kind == .focus ? store.data.settings.focusColor : store.data.settings.breakColor)
      .color
  }

  init(store: AppStore, adjustmentDirection: Int? = nil) {
    self.store = store
    _adjustmentDirection = State(initialValue: adjustmentDirection)
  }

  var body: some View {
    ScrollView {
      VStack(spacing: 18) {
        SessionIdentity(store: store).padding(.top, 8)
        FocusDial(remaining: store.remaining, duration: store.timer.duration, accent: accent)
        timeControls
        HStack(spacing: 24) {
          if store.timer.kind == .focus {
            Button {
              if active { confirmingBreak = true } else { store.startBreakNow() }
            } label: {
              Label("Break", systemImage: "cup.and.saucer")
            }.help("Start a break now").foregroundStyle(store.data.settings.breakColor.color)
          } else if active {
            Button {
              store.endBreak()
            } label: {
              Label("End break", systemImage: "briefcase")
            }.help("End break · Return to focus").foregroundStyle(
              store.data.settings.focusColor.color)
          }
          Button {
            confirmingAbandon = true
          } label: {
            Label("Abandon", systemImage: "stop")
          }.disabled(!active).help("Abandon interval")
        }.buttonStyle(IntervalIconButton()).foregroundStyle(.primary)
        if let message = store.inAppNotification ?? store.recoveryMessage {
          Text(message).font(.caption).foregroundStyle(.secondary)
        }
        if let error = store.audioError {
          Label(error, systemImage: "speaker.slash").font(.caption).foregroundStyle(.orange)
        }
        upcomingReminders
      }.padding(24).frame(maxWidth: .infinity)
    }.defaultScrollAnchor(.center, for: .alignment)
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

  private var timeControls: some View {
    VStack(spacing: 6) {
      HStack(spacing: 12) {
        adjustmentButton(direction: -1)
        Group {
          if active, let start = store.timer.startedAt, let end = store.timer.deadline {
            Text(
              "\(start.formatted(date: .omitted, time: .shortened)) → \(end.formatted(date: .omitted, time: .shortened))"
            )
            .font(.callout).monospacedDigit().foregroundStyle(.secondary)
            .lineLimit(1).minimumScaleFactor(0.85)
            .help("Started \(start.formatted()) · Ends \(end.formatted())")
            .accessibilityLabel(
              "Started \(start.formatted(date: .omitted, time: .shortened)), ends \(end.formatted(date: .omitted, time: .shortened))"
            )
          } else {
            Button(action: store.startSession) {
              Label("Start", systemImage: "play.fill")
            }.buttonStyle(IntervalIconButton()).foregroundStyle(accent).help("Start interval")
          }
        }.frame(maxWidth: .infinity)
        adjustmentButton(direction: 1)
      }
      HStack(spacing: 8) {
        ForEach([10, 15], id: \.self) { minutes in
          Button("\((adjustmentDirection ?? 1) > 0 ? "+" : "−")\(minutes)m") {
            store.adjustCurrentTime(by: Double((adjustmentDirection ?? 1) * minutes * 60))
          }.buttonStyle(.plain).font(.caption.weight(.medium))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(.white.opacity(0.07), in: Capsule())
            .accessibilityLabel(
              "\((adjustmentDirection ?? 1) > 0 ? "Add" : "Remove") \(minutes) minutes")
        }
      }.opacity(adjustmentDirection == nil ? 0 : 1)
        .allowsHitTesting(adjustmentDirection != nil)
        .accessibilityHidden(adjustmentDirection == nil)
    }.contentShape(Rectangle())
      .onHover { hovering in if !hovering { adjustmentDirection = nil } }
  }

  private func adjustmentButton(direction: Int) -> some View {
    Button {
      store.adjustCurrentTime(by: Double(direction * 300))
    } label: {
      Image(systemName: direction > 0 ? "plus" : "minus")
    }.buttonStyle(IntervalIconButton())
      .disabled(direction > 0 ? store.remaining >= 10_800 : store.remaining <= 60)
      .accessibilityLabel(direction > 0 ? "Add 5 minutes" : "Remove 5 minutes")
      .help(
        direction > 0
          ? "Add 5 minutes · Right-click for more" : "Remove 5 minutes · Right-click for more"
      )
      .onHover { hovering in if hovering { adjustmentDirection = direction } }
      .contextMenu {
        ForEach([5, 10, 15], id: \.self) { minutes in
          Button("\(direction > 0 ? "Add" : "Remove") \(minutes) minutes") {
            store.adjustCurrentTime(by: Double(direction * minutes * 60))
          }
        }
      }
  }

  private var upcomingReminders: some View {
    let reminders = store.data.reminders.filter { $0.isEnabled && $0.effectiveDueAt != nil }
      .sorted { $0.effectiveDueAt! < $1.effectiveDueAt! }
    return VStack(alignment: .leading, spacing: 14) {
      Text("Upcoming").font(.caption.weight(.medium)).foregroundStyle(.secondary)
      if reminders.isEmpty {
        Text("No reminders scheduled").font(.caption).foregroundStyle(.secondary)
      }
      ForEach(Array(reminders.prefix(3))) { reminder in
        HStack(spacing: 10) {
          Text(reminder.emoji).font(.system(size: 19)).frame(width: 24)
          Text(reminder.title).font(.callout).lineLimit(1)
          Spacer(minLength: 8)
          Text(reminderStatus(reminder)).font(.caption).monospacedDigit().foregroundStyle(
            .secondary)
        }
      }
    }
  }

  private func reminderStatus(_ reminder: Reminder) -> String {
    if reminder.suppressDuringFocus && store.timer.kind == .focus && store.timer.status == .running
    {
      return "After focus"
    }
    if reminder.suppressDuringCalendar
      && store.calendarService.todayEvents.contains(where: {
        $0.isEligibleForReminderSuppression && $0.start <= store.now && $0.end > store.now
      })
    {
      return "After event"
    }
    let remaining = (reminder.effectiveDueAt ?? store.now).timeIntervalSince(store.now)
    return remaining <= 0 ? "When idle" : "In \(durationString(remaining))"
  }
}

private struct FocusDial: View {
  let remaining: TimeInterval
  let duration: TimeInterval
  let accent: Color
  private var fraction: Double { min(1, max(0, remaining / max(1, duration))) }

  var body: some View {
    ZStack {
      ForEach(0..<60) { tick in
        Capsule().fill(tick % 5 == 0 ? .white.opacity(0.5) : .white.opacity(0.15))
          .frame(width: tick % 5 == 0 ? 2 : 1, height: tick % 5 == 0 ? 12 : 6)
          .offset(y: -116).rotationEffect(.degrees(Double(tick) * 6))
      }
      Circle().fill(accent.opacity(0.06)).padding(27)
      Circle().stroke(.white.opacity(0.06), lineWidth: 6).padding(27)
      Circle().trim(from: 0, to: fraction)
        .stroke(accent.gradient, style: StrokeStyle(lineWidth: 6, lineCap: .round))
        .rotationEffect(.degrees(-90)).padding(27)
      Circle().fill(accent).frame(width: 10, height: 10)
        .shadow(color: accent.opacity(0.5), radius: 5)
        .offset(y: -98).rotationEffect(.degrees(fraction * 360))
      Text(durationString(remaining))
        .font(.system(size: 42, weight: .light, design: .rounded)).monospacedDigit()
    }.frame(width: 250, height: 250)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("Time remaining").accessibilityValue(spokenDuration(remaining))
  }
}

struct FocusDayPanel: View {
  @Bindable var store: AppStore
  @State private var newTodo = ""
  @State private var selectedSessionID: UUID?
  private var sessions: [SessionRecord] {
    store.data.sessions.filter {
      $0.kind == .focus && Calendar.autoupdatingCurrent.isDate($0.endedAt, inSameDayAs: store.now)
    }
  }
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        Text("To-dos").font(.headline)
        VStack(spacing: 8) {
          ForEach(store.data.todos) { todo in
            TodoRow(store: store, todo: todo)
          }
          HStack(spacing: 10) {
            Image(systemName: "plus").foregroundStyle(.secondary).frame(width: 18)
            TextField("Add a to-do…", text: $newTodo)
              .textFieldStyle(.plain).onSubmit(addTodo)
              .accessibilityLabel("New to-do")
            Button(action: addTodo) {
              Image(systemName: "return").frame(width: 24, height: 24)
            }.buttonStyle(.plain).foregroundStyle(.secondary)
              .disabled(newTodo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
              .help("Add to-do").accessibilityLabel("Add to-do")
          }.padding(.vertical, 5)
        }.font(.body)
        Text("Today").font(.headline).padding(.top, 12)
        HStack(spacing: 28) {
          VStack(alignment: .leading, spacing: 4) {
            Text("\(Int(sessions.reduce(0) { $0 + $1.activeDuration } / 60))m")
              .font(.title2.weight(.medium)).monospacedDigit()
            Text("Logged focus").font(.caption).foregroundStyle(.secondary)
          }
          VStack(alignment: .leading, spacing: 4) {
            Text("\(sessions.filter { $0.outcome == .completed }.count)")
              .font(.title2.weight(.medium)).monospacedDigit()
            Text("Completed").font(.caption).foregroundStyle(.secondary)
          }
        }
        HStack {
          Text("Timeline").font(.headline)
          Spacer()
          Text(store.now.formatted(.dateTime.month(.abbreviated).day()))
            .font(.caption).foregroundStyle(.secondary)
        }.padding(.top, 12)
        dayTimeline
      }.padding(24)
    }.sheet(
      isPresented: Binding(
        get: { selectedSessionID != nil }, set: { if !$0 { selectedSessionID = nil } }
      )
    ) {
      if let session = store.data.sessions.first(where: { $0.id == selectedSessionID }) {
        VStack(spacing: 0) {
          HStack {
            Text("Session").font(.headline)
            Spacer()
            Button("Done") { selectedSessionID = nil }.keyboardShortcut(.cancelAction)
          }.padding(20)
          SessionInspector(store: store, session: session)
        }.frame(width: 460, height: 500).background(GlassBackground())
      }
    }
  }

  private func addTodo() {
    store.addTodo(newTodo)
    newTodo = ""
  }

  private var dayItems: [HistoryItem] {
    let logs = store.data.sessions.filter {
      Calendar.autoupdatingCurrent.isDate($0.endedAt, inSameDayAs: store.now)
    }.map(HistoryItem.session)
    let events =
      store.calendarService.isEnabled && store.calendarService.authorizationState == .fullAccess
      ? store.calendarService.todayEvents.map(HistoryItem.calendar) : []
    return (logs + events).sorted {
      $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start
    }
  }

  private var dayTimeline: some View {
    VStack(alignment: .leading, spacing: 0) {
      if dayItems.isEmpty {
        Text("No activity yet today").font(.callout).foregroundStyle(.secondary)
      }
      ForEach(dayItems) { item in
        HStack(alignment: .top, spacing: 10) {
          VStack(spacing: 4) {
            Circle().fill(.white.opacity(0.4)).frame(width: 5, height: 5)
            Rectangle().fill(IntervalTheme.border).frame(width: 1)
          }.frame(width: 6).padding(.top, 8)
          Group {
            switch item {
            case .session(let session):
              Button {
                selectedSessionID = session.id
              } label: {
                SessionRow(session: session, showsReflection: false)
                  .frame(maxWidth: .infinity, alignment: .leading)
              }.buttonStyle(.plain)
            case .calendar(let event): CalendarEventRow(event: event)
            }
          }
          .padding(.bottom, 18)
        }.fixedSize(horizontal: false, vertical: true)
      }
      if !store.calendarService.isEnabled || store.calendarService.authorizationState != .fullAccess
      {
        SettingsLink { Label("Connect your calendar", systemImage: "calendar.badge.plus") }
          .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary).padding(.top, 12)
      } else if store.calendarService.selectedCalendarIDs.isEmpty {
        SettingsLink { Label("Choose calendars", systemImage: "calendar.badge.plus") }
          .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary).padding(.top, 12)
      }
    }
  }
}

private struct TodoRow: View {
  @Bindable var store: AppStore
  let todo: TodoItem
  @State private var title: String
  @FocusState private var isEditing: Bool

  init(store: AppStore, todo: TodoItem) {
    self.store = store
    self.todo = todo
    _title = State(initialValue: todo.title)
  }

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 10) {
      Toggle("", isOn: Binding(get: { todo.isCompleted }, set: { _ in store.toggleTodo(todo.id) }))
        .toggleStyle(.checkbox).labelsHidden().tint(.accentColor)
        .accessibilityLabel("Complete \(todo.title)")
      TextField("To-do", text: $title, axis: .vertical)
        .textFieldStyle(.plain).lineLimit(1...5)
        .strikethrough(todo.isCompleted)
        .foregroundStyle(todo.isCompleted ? .secondary : .primary)
        .focused($isEditing)
        .accessibilityLabel("To-do title")
        .onChange(of: title) { _, value in store.updateTodoTitle(todo.id, title: value) }
        .onChange(of: isEditing) { _, editing in
          if !editing { title = todo.title }
        }
        .onSubmit { isEditing = false }
      Button {
        store.deleteTodo(todo.id)
      } label: {
        Image(systemName: "xmark").font(.caption).frame(width: 24, height: 24)
      }.buttonStyle(.plain).foregroundStyle(.tertiary)
        .help("Delete to-do").accessibilityLabel("Delete \(todo.title)")
    }.padding(.vertical, 5)
  }
}
