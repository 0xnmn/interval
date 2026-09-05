import IntervalCore
import SwiftUI

enum Destination: String, CaseIterable, Identifiable {
  case focus = "Focus"
  case history = "History"
  case reminders = "Reminders"
  var id: Self { self }
  var icon: String {
    switch self {
    case .focus: "timer"
    case .history: "clock.arrow.circlepath"
    case .reminders: "checklist"
    }
  }
}

struct MainView: View {
  @Bindable var store: AppStore

  init(store: AppStore) { self.store = store }

  var body: some View {
    ZStack {
      GlassBackground()
      HStack(spacing: 0) {
        VStack(alignment: .leading, spacing: 6) {
          HStack(spacing: 9) {
            Image(systemName: "circle.hexagongrid.fill").foregroundStyle(IntervalTheme.accent)
            Text("INTERVAL").font(.system(.headline, design: .rounded).weight(.bold)).tracking(1.5)
          }.padding(.horizontal, 12).padding(.bottom, 18)
          ForEach(Destination.allCases) { item in
            let selected = (store.selection ?? .focus) == item
            Button {
              store.selection = item
            } label: {
              Label(item.rawValue, systemImage: item.icon)
                .font(.callout.weight(selected ? .semibold : .regular))
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 11)
                .frame(height: 36)
                .background(
                  selected ? .white.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 8))
            }.buttonStyle(.plain).foregroundStyle(selected ? .primary : .secondary)
              .accessibilityAddTraits(selected ? .isSelected : [])
          }
          Spacer()
          if store.timer.status == .running || store.timer.status == .paused {
            VStack(alignment: .leading, spacing: 5) {
              Text(store.timer.status == .running ? "IN PROGRESS" : "PAUSED")
                .font(.caption2.weight(.bold)).tracking(1).foregroundStyle(IntervalTheme.accent)
              Text(durationString(store.remaining)).font(
                .system(.title3, design: .monospaced).weight(.medium))
              Text(store.timer.kind.title).font(.caption).foregroundStyle(.secondary)
            }.padding(11).frame(maxWidth: .infinity, alignment: .leading).intervalPanel()
          }
          SettingsLink {
            Label("Settings", systemImage: "gearshape").frame(
              maxWidth: .infinity, alignment: .leading)
          }.buttonStyle(.plain).foregroundStyle(.secondary).padding(11)
        }.padding(12).frame(width: 170)
          .background(.black.opacity(0.20))
          .overlay(alignment: .trailing) { Rectangle().fill(IntervalTheme.border).frame(width: 1) }
        Group {
          switch store.selection ?? .focus {
          case .focus: FocusView(store: store)
          case .history: HistoryView(store: store)
          case .reminders: RemindersView(store: store)
          }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .frame(minWidth: 940, minHeight: 540)
    .tint(IntervalTheme.accent).preferredColorScheme(.dark)
    .safeAreaInset(edge: .bottom) {
      if let error = store.persistenceError {
        Label(error, systemImage: "exclamationmark.triangle.fill")
          .font(.callout).foregroundStyle(.red).padding(12)
          .frame(maxWidth: .infinity).background(.regularMaterial)
      }
    }
  }
}

struct FocusView: View {
  @Bindable var store: AppStore
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var confirmingAbandon = false
  @State private var showsNotes = true
  var body: some View {
    VStack(spacing: 0) {
      HStack {
        VStack(alignment: .leading, spacing: 3) {
          Text("Focus").font(.title2.bold())
          Text("One interval at a time.").font(.caption).foregroundStyle(.secondary)
        }
        Spacer()
        Button {
          showsNotes.toggle()
        } label: {
          Label(showsNotes ? "Hide notes" : "Show notes", systemImage: "sidebar.right")
        }.buttonStyle(.borderless).accessibilityLabel(showsNotes ? "Hide notes" : "Show notes")
      }.padding(.horizontal, 26).padding(.vertical, 18)
      Divider().opacity(0.6)
      ScrollView {
        VStack(spacing: 18) {
          HStack(alignment: .top, spacing: 18) {
            VStack(spacing: 14) {
              Picker(
                "Interval type", selection: Binding(get: { store.timer.kind }, set: store.choose)
              ) {
                ForEach(TimerKind.allCases, id: \.self) { Text($0.title).tag($0) }
              }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: 360).disabled(
                store.timer.status != .ready)
              ZStack {
                Circle().stroke(.white.opacity(0.07), lineWidth: 8)
                Circle().trim(from: 0, to: progress).stroke(
                  IntervalTheme.accent, style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90)).animation(
                  reduceMotion ? nil : .smooth, value: progress)
                VStack(spacing: 7) {
                  Text(store.timer.kind.title.uppercased()).font(.caption.weight(.bold)).tracking(2)
                    .foregroundStyle(.secondary)
                  Text(durationString(store.remaining)).font(
                    .system(size: 54, weight: .semibold, design: .monospaced)
                  )
                  .monospacedDigit().contentTransition(reduceMotion ? .identity : .numericText())
                  .accessibilityLabel(
                    timerAccessibilityLabel)
                  Text(statusText).font(.caption).foregroundStyle(.secondary)
                }
              }.frame(width: 268, height: 268).padding(.vertical, 2)
              HStack(spacing: 12) {
                Button(action: store.startOrToggle) {
                  Label(primaryTitle, systemImage: primaryIcon).frame(minWidth: 105)
                }
                .buttonStyle(IntervalPrimaryButton())
                if store.timer.status == .running || store.timer.status == .paused {
                  Button("Abandon", role: .destructive) { confirmingAbandon = true }.buttonStyle(
                    .plain
                  )
                  .foregroundStyle(.red.opacity(0.9))
                }
              }
              if store.timer.kind == .focus { cycleIndicator }
            }.padding(22).frame(maxWidth: .infinity).intervalPanel()
            if showsNotes && store.completionSessionID == nil { notesPane.frame(width: 250) }
          }
          if let id = store.completionSessionID {
            ReflectionView(store: store, sessionID: id).padding(20).intervalPanel()
          }
          if !showsNotes || store.completionSessionID != nil {
            HStack(spacing: 14) { messageStack }
              .font(.caption).padding(.horizontal, 4).frame(
                maxWidth: .infinity, alignment: .leading)
          }
        }.padding(22)
      }
    }
    .alert("Abandon this interval?", isPresented: $confirmingAbandon) {
      Button("Keep Going", role: .cancel) {}
      Button("Abandon", role: .destructive, action: store.abandon)
    } message: {
      Text("Elapsed active time will be kept in History.")
    }
  }
  private var progress: Double {
    guard store.timer.duration > 0 else { return 0 }
    return min(1, max(0, 1 - store.remaining / store.timer.duration))
  }
  private var cycleIndicator: some View {
    let total = max(1, store.data.settings.longBreakEvery)
    let current = store.data.completedFocusCount % total
    return VStack(spacing: 7) {
      HStack(spacing: 7) {
        ForEach(0..<total, id: \.self) { index in
          Circle().fill(index <= current ? IntervalTheme.accent : .white.opacity(0.14)).frame(
            width: 6, height: 6
          ).accessibilityHidden(true)
        }
      }
      Text("Cycle \(current + 1) of \(total)").font(.caption).foregroundStyle(.secondary)
    }.accessibilityElement(children: .combine)
  }
  private var notesPane: some View {
    VStack(alignment: .leading, spacing: 10) {
      Label("Notes", systemImage: "square.and.pencil").font(.headline)
      Text("Keep context close without leaving the interval.").font(.caption).foregroundStyle(
        .secondary)
      TextEditor(text: Binding(get: { store.data.scratchpad }, set: store.updateScratchpad))
        .scrollContentBackground(.hidden).padding(8).frame(maxHeight: .infinity)
        .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 9)).accessibilityLabel(
          "Global scratchpad")
      messageStack
    }.padding(16).frame(minHeight: 410, maxHeight: .infinity).intervalPanel()
  }
  @ViewBuilder private var messageStack: some View {
    if let notice = store.inAppNotification {
      Label(notice, systemImage: "bell.fill").foregroundStyle(IntervalTheme.accent)
    }
    if let error = store.persistenceError {
      Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
    } else if store.didSave {
      Label("Saved", systemImage: "checkmark.circle").foregroundStyle(.secondary)
    } else {
      Text("Changes save automatically.").foregroundStyle(.secondary)
    }
    if let recovery = store.recoveryMessage {
      Label(recovery, systemImage: "pause.circle").foregroundStyle(.secondary)
    }
    if let error = store.audioError {
      Label(error, systemImage: "speaker.slash").foregroundStyle(.orange)
    }
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
    case .ready:
      store.timer.kind == .focus
        ? "Ready when you are." : "Your focus is complete. Take a break when ready."
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
    VStack(spacing: 0) {
      HStack {
        VStack(alignment: .leading, spacing: 3) {
          Text("History").font(.title2.bold())
          Text(selectedDay.formatted(.dateTime.weekday(.wide).month(.wide).day().year()))
            .font(.caption).foregroundStyle(.secondary)
        }
        Spacer()
        Button("Today") {
          month = store.now
          selectedDay = store.now
          selectedSession = nil
          store.calendarService.show(month: store.now)
        }
        .buttonStyle(.bordered)
      }.padding(.horizontal, 26).padding(.vertical, 18)
      Divider().opacity(0.6)
      HStack(spacing: 0) {
        VStack(spacing: 14) {
          HStack {
            Button(action: { changeMonth(by: -1) }) { Image(systemName: "chevron.left") }
              .accessibilityLabel("Previous month")
            Spacer()
            Text(month.formatted(.dateTime.month(.wide).year())).font(.headline)
            Spacer()
            Button(action: { changeMonth(by: 1) }) { Image(systemName: "chevron.right") }
              .accessibilityLabel("Next month")
          }
          LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
            ForEach(CalendarDates.weekdaySymbols(calendar: calendar), id: \.self) {
              Text($0).font(.caption).foregroundStyle(.secondary)
            }
            ForEach(
              Array(CalendarDates.monthGrid(containing: month, calendar: calendar).enumerated()),
              id: \.offset
            ) { _, date in
              if let date {
                let sessionCount = sessionCount(on: date)
                let eventCount = calendarEventCount(on: date)
                Button("\(calendar.component(.day, from: date))") {
                  selectedDay = date
                  selectedSession = nil
                }
                .buttonStyle(.plain).frame(maxWidth: .infinity, minHeight: 28)
                .background(
                  calendar.isDate(date, inSameDayAs: selectedDay)
                    ? Color.teal.opacity(0.22) : .clear,
                  in: Circle()
                )
                .overlay(alignment: .bottom) {
                  HStack(spacing: 3) {
                    if sessionCount > 0 { Circle().fill(.teal).frame(width: 4, height: 4) }
                    if eventCount > 0 { Circle().fill(.blue).frame(width: 4, height: 4) }
                  }
                }
                .accessibilityLabel(
                  "\(date.formatted(date: .complete, time: .omitted)), \(sessionCount) session\(sessionCount == 1 ? "" : "s"), \(eventCount) calendar event\(eventCount == 1 ? "" : "s")"
                )
                .accessibilityAddTraits(
                  calendar.isDate(date, inSameDayAs: selectedDay) ? .isSelected : [])
              } else {
                Color.clear.frame(height: 28)
              }
            }
          }
          HStack(spacing: 14) {
            Label("Sessions", systemImage: "circle.fill").foregroundStyle(.teal)
            Label("Calendar events", systemImage: "circle.fill").foregroundStyle(.blue)
          }.font(.caption).accessibilityElement(children: .combine).accessibilityLabel(
            "Legend: teal marks sessions; blue marks calendar events")
          Divider().opacity(0.6)
          if dayItems.isEmpty {
            ContentUnavailableView(
              emptyTitle, systemImage: "calendar", description: Text(emptyDescription)
            )
            .frame(minHeight: 170, maxHeight: .infinity)
          } else {
            ScrollView {
              LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(dayItems) { item in
                  switch item {
                  case .calendar(let event): CalendarEventRow(event: event)
                  case .session(let session):
                    Button {
                      selectedSession = session.id
                    } label: {
                      SessionRow(session: session).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .background(
                          selectedSession == session.id ? Color.teal.opacity(0.16) : .clear,
                          in: RoundedRectangle(cornerRadius: 7))
                    }.buttonStyle(.plain)
                  }
                }
              }
            }.frame(minHeight: 170, maxHeight: .infinity)
          }
        }.padding(18).frame(minWidth: 350, maxWidth: .infinity, maxHeight: .infinity)
          .intervalPanel().padding(18)
        Rectangle().fill(IntervalTheme.border).frame(width: 1)
        if let id = selectedSession, let session = store.data.sessions.first(where: { $0.id == id })
        {
          SessionInspector(store: store, session: session).frame(minWidth: 290)
        } else {
          daySummary.frame(minWidth: 290)
        }
      }
    }.task { store.calendarService.show(month: month) }
  }
  private var daySummary: some View {
    VStack(alignment: .leading, spacing: 14) {
      Image(systemName: "calendar.day.timeline.left").font(.title).foregroundStyle(
        IntervalTheme.accent)
      Text(selectedDay.formatted(.dateTime.weekday(.wide).month(.wide).day())).font(.title3.bold())
      if daySessions.isEmpty {
        Text("No interval sessions were recorded on this day.").foregroundStyle(.secondary)
      } else {
        Text("\(daySessions.count) interval\(daySessions.count == 1 ? "" : "s") recorded")
        Text("Select a session in the timeline to review its timing and reflection.")
          .font(.callout).foregroundStyle(.secondary)
      }
      if !dayCalendarEvents.isEmpty {
        Label(
          "\(dayCalendarEvents.count) calendar event\(dayCalendarEvents.count == 1 ? "" : "s")",
          systemImage: "calendar"
        )
        .font(.callout).foregroundStyle(.blue)
      }
      Spacer()
    }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
  private var daySessions: [SessionRecord] {
    store.data.sessions.filter { calendar.isDate($0.endedAt, inSameDayAs: selectedDay) }.sorted {
      $0.endedAt < $1.endedAt
    }
  }
  private var dayCalendarEvents: [CalendarEventSnapshot] {
    store.calendarService.events(on: selectedDay, calendar: calendar)
  }
  private var dayItems: [HistoryItem] {
    (daySessions.map(HistoryItem.session) + dayCalendarEvents.map(HistoryItem.calendar)).sorted {
      $0.start < $1.start
    }
  }
  private var emptyTitle: String {
    store.data.settings.calendarIntegrationEnabled
      && store.calendarService.authorizationState != .fullAccess
      ? "Calendar unavailable" : "Nothing this day"
  }
  private var emptyDescription: String {
    if !store.data.settings.calendarIntegrationEnabled {
      return "No sessions. Apple Calendar integration is disabled."
    }
    if store.calendarService.authorizationState != .fullAccess {
      return "No sessions. Calendar permission is unavailable."
    }
    if store.data.settings.selectedCalendarIDs.isEmpty {
      return "No sessions. No calendars are selected."
    }
    return "No sessions or Apple Calendar events."
  }
  private func sessionCount(on date: Date) -> Int {
    store.data.sessions.count { calendar.isDate($0.endedAt, inSameDayAs: date) }
  }
  private func calendarEventCount(on date: Date) -> Int {
    store.calendarService.events(on: date, calendar: calendar).count
  }
  private func changeMonth(by value: Int) {
    guard let newMonth = calendar.date(byAdding: .month, value: value, to: month),
      let interval = calendar.dateInterval(of: .month, for: newMonth),
      let range = calendar.range(of: .day, in: .month, for: newMonth)
    else { return }
    let day = min(calendar.component(.day, from: selectedDay), range.count)
    month = newMonth
    store.calendarService.show(month: newMonth)
    selectedDay =
      calendar.date(byAdding: .day, value: day - 1, to: interval.start) ?? interval.start
    selectedSession = nil
  }
}

private enum HistoryItem: Identifiable {
  case session(SessionRecord)
  case calendar(CalendarEventSnapshot)

  var id: String {
    switch self {
    case .session(let value): "session-\(value.id)"
    case .calendar(let value): "calendar-\(value.id)"
    }
  }
  var start: Date {
    switch self {
    case .session(let value): value.startedAt
    case .calendar(let value): value.start
    }
  }
}

struct CalendarEventRow: View {
  let event: CalendarEventSnapshot
  var body: some View {
    HStack(alignment: .top) {
      Image(systemName: "calendar").foregroundStyle(.blue)
      VStack(alignment: .leading, spacing: 2) {
        Text(event.title).font(.headline)
        Text("Apple Calendar · \(event.calendarName)").font(.caption.weight(.medium))
          .foregroundStyle(.blue)
        Text(timeDescription + statusDescription).font(.caption).foregroundStyle(.secondary)
      }
    }.padding(.vertical, 5).padding(.horizontal, 8).frame(maxWidth: .infinity, alignment: .leading)
  }
  private var timeDescription: String {
    if event.allDay { return "All day" }
    return
      "\(event.start.formatted(date: .omitted, time: .shortened))–\(event.end.formatted(date: .omitted, time: .shortened))"
  }
  private var statusDescription: String {
    switch event.status {
    case .confirmed: ""
    case .tentative: " · Tentative"
    case .canceled: " · Canceled — does not suppress reminders"
    case .declined: " · Declined — does not suppress reminders"
    }
  }
}

struct SessionRow: View {
  let session: SessionRecord
  var body: some View {
    HStack {
      Image(systemName: session.outcome == .completed ? "checkmark.circle.fill" : "xmark.circle")
        .foregroundStyle(session.outcome == .completed ? .teal : .secondary)
      VStack(alignment: .leading) {
        Text(session.kind.title).font(.headline)
        Text("Interval session").font(.caption.weight(.medium)).foregroundStyle(.teal)
        Text(
          "\(session.startedAt.formatted(date: .omitted, time: .shortened))–\(session.endedAt.formatted(date: .omitted, time: .shortened)) · \(session.isDurationEstimated ? "≈ " : "")\(durationString(session.activeDuration)) · \(session.outcome.rawValue.capitalized)"
        ).font(.caption).foregroundStyle(.secondary)
        if session.isDurationEstimated {
          Text("Estimated duration · early version").font(.caption).foregroundStyle(.secondary)
        }
        if let feedback = session.feedback { Text(feedback.capitalized).font(.caption) }
      }
    }.padding(.vertical, 3)
  }
}

struct ReflectionView: View {
  @Bindable var store: AppStore
  let sessionID: UUID
  private var session: SessionRecord? { store.data.sessions.first { $0.id == sessionID } }
  private var feedback: Binding<SessionFeedback?> {
    Binding(
      get: { session?.feedback.flatMap(SessionFeedback.init(rawValue:)) },
      set: { store.updateSession(id: sessionID, feedback: $0, journal: session?.journal ?? "") })
  }
  private var journal: Binding<String> {
    Binding(
      get: { session?.journal ?? "" },
      set: { store.updateSession(id: sessionID, feedback: feedback.wrappedValue, journal: $0) })
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Label("Focus complete — how did it feel?", systemImage: "sparkles").font(.title3.bold())
      HStack {
        ForEach(SessionFeedback.allCases, id: \.self) { value in
          let selected = feedback.wrappedValue == value
          Button {
            setFeedback(value)
          } label: {
            Label(value.title, systemImage: selected ? "checkmark.circle.fill" : "circle")
          }
          .buttonStyle(.bordered).tint(selected ? IntervalTheme.accent : .secondary)
          .accessibilityAddTraits(feedback.wrappedValue == value ? .isSelected : [])
        }
      }
      TextField("Optional reflection", text: journal)
      HStack {
        Text("Your session is already saved. Your suggested break is ready.").font(.caption)
          .foregroundStyle(.secondary)
        Spacer()
        Button("Later", action: store.deferReflection).buttonStyle(.plain)
        Button("Done", action: store.deferReflection).buttonStyle(IntervalPrimaryButton())
      }
    }
  }
  private func setFeedback(_ value: SessionFeedback) { feedback.wrappedValue = value }
}

struct SessionInspector: View {
  @Bindable var store: AppStore
  let session: SessionRecord
  var body: some View {
    Form {
      Section("Session") {
        LabeledContent("Started", value: session.startedAt.formatted())
        LabeledContent(
          session.isDurationEstimated ? "Estimated active" : "Active",
          value: (session.isDurationEstimated ? "≈ " : "") + durationString(session.activeDuration))
        if session.isDurationEstimated {
          Text("Estimated from the recorded time range; this early version did not record pauses.")
            .font(.caption).foregroundStyle(.secondary)
        }
        LabeledContent("Outcome", value: session.outcome.rawValue.capitalized)
      }
      Section("Reflection") {
        Picker(
          "Focus",
          selection: Binding<SessionFeedback?>(
            get: { session.feedback.flatMap(SessionFeedback.init(rawValue:)) },
            set: {
              store.updateSession(id: session.id, feedback: $0, journal: session.journal ?? "")
            })
        ) {
          Text("Pending").tag(SessionFeedback?.none)
          ForEach(SessionFeedback.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
        }
        TextEditor(
          text: Binding(
            get: { session.journal ?? "" },
            set: {
              store.updateSession(
                id: session.id, feedback: session.feedback.flatMap(SessionFeedback.init(rawValue:)),
                journal: $0)
            })
        ).frame(minHeight: 120)
      }
    }.formStyle(.grouped).scrollContentBackground(.hidden).padding(18).intervalPanel().padding(18)
  }
}

struct PlaceholderView: View {
  let title: String
  let icon: String
  let message: String
  var body: some View {
    ContentUnavailableView(title, systemImage: icon, description: Text(message)).navigationTitle(
      title)
  }
}

struct MenuBarView: View {
  @Bindable var store: AppStore
  @Environment(\.openWindow) private var openWindow
  @State private var confirmingAbandon = false
  @State private var quickNote = ""
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Label("INTERVAL", systemImage: "circle.hexagongrid.fill").font(.caption.bold()).tracking(
          1.2
        )
        .foregroundStyle(IntervalTheme.accent)
        Spacer()
        Text(store.timer.status.rawValue.uppercased()).font(.caption2.weight(.bold))
          .foregroundStyle(.secondary)
      }.padding(.bottom, 13)
      VStack(alignment: .leading, spacing: 5) {
        Text(store.timer.kind.title).font(.callout.weight(.semibold)).foregroundStyle(.secondary)
        Text(durationString(store.remaining)).font(
          .system(size: 42, weight: .semibold, design: .monospaced)
        ).monospacedDigit()
        if store.timer.kind == .focus {
          Text(
            "Cycle \(store.data.completedFocusCount % max(1, store.data.settings.longBreakEvery) + 1) of \(max(1, store.data.settings.longBreakEvery))"
          ).font(.caption).foregroundStyle(.secondary).padding(.bottom, 6)
        }
        HStack(spacing: 8) {
          Button(primaryTitle, action: store.startOrToggle).buttonStyle(IntervalPrimaryButton())
          if store.timer.status == .running || store.timer.status == .paused {
            Button("Abandon", role: .destructive) { confirmingAbandon = true }.buttonStyle(.plain)
              .foregroundStyle(.red)
          }
        }
      }.padding(13).frame(maxWidth: .infinity, alignment: .leading).intervalPanel()
      if store.completionSessionID != nil {
        Button("Open Reflection") {
          store.showFocus()
          openWindow(id: "main")
          NSApp.activate(ignoringOtherApps: true)
        }
      }
      Divider().padding(.vertical, 12)
      if let warningReminder {
        VStack(alignment: .leading, spacing: 6) {
          Text("Warning: \(warningReminder.title)").font(.caption.weight(.semibold))
          HStack {
            Button("Postpone this time · 5min") { store.snoozeReminder(warningReminder.id) }
            Button("Skip") { store.dismissReminder(warningReminder.id) }
          }
        }.frame(maxWidth: .infinity, alignment: .leading)
        Divider().padding(.vertical, 10)
      }
      if let reminder = store.nextReminder {
        VStack(alignment: .leading, spacing: 5) {
          Text("Next: \(reminder.title)").font(.caption.weight(.semibold))
          Text(
            reminder.effectiveDueAt?.formatted(date: .omitted, time: .shortened) ?? "Not scheduled"
          ).font(.caption).foregroundStyle(.secondary)
          Button("Postpone this time · 5min") { store.snoozeReminder(reminder.id) }
        }.frame(maxWidth: .infinity, alignment: .leading)
        Divider().padding(.vertical, 10)
      }
      Text("QUICK NOTE").font(.caption2.bold()).tracking(1).foregroundStyle(.secondary).padding(
        .bottom, 6)
      HStack(spacing: 7) {
        TextField("Quick note", text: $quickNote).onSubmit {
          store.appendQuickNote(quickNote)
          quickNote = ""
        }
        Button("Add") {
          store.appendQuickNote(quickNote)
          quickNote = ""
        }.disabled(quickNote.isEmpty)
      }
      Divider().padding(.vertical, 12)
      HStack(spacing: 12) {
        Button("Open Interval") {
          openWindow(id: "main")
          NSApp.activate(ignoringOtherApps: true)
        }
        SettingsLink { Text("Settings") }
        Spacer()
        Button("Quit") { NSApp.terminate(nil) }
      }
    }.padding(14).frame(width: 320).background(IntervalTheme.surface).tint(IntervalTheme.accent)
      .preferredColorScheme(.dark)
      .accessibilityElement(children: .contain)
      .accessibilityLabel(
        "\(store.timer.kind.title), \(store.timer.status.rawValue), \(spokenDuration(store.remaining)) remaining"
      )
      .alert("Abandon this interval?", isPresented: $confirmingAbandon) {
        Button("Keep Going", role: .cancel) {}
        Button("Abandon", role: .destructive, action: store.abandon)
      } message: {
        Text("Elapsed active time will be kept in History.")
      }
  }
  private var primaryTitle: String {
    store.timer.status == .running
      ? "Pause"
      : store.timer.status == .paused
        ? "Resume" : store.timer.kind == .focus ? "Start Focus" : "Start Break"
  }
  private var warningReminder: Reminder? {
    guard case .warning(let id, _, _) = store.reminderOverlay else { return nil }
    return store.data.reminders.first { $0.id == id }
  }
}

func durationString(_ seconds: TimeInterval) -> String {
  let total = max(0, Int(ceil(seconds)))
  return String(format: "%02d:%02d", total / 60, total % 60)
}

func spokenDuration(_ seconds: TimeInterval) -> String {
  let total = max(0, Int(ceil(seconds)))
  let minutes = total / 60
  let remainder = total % 60
  return
    "\(minutes) minute\(minutes == 1 ? "" : "s"), \(remainder) second\(remainder == 1 ? "" : "s")"
}
