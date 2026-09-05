import IntervalCore
import SwiftUI

enum Destination: String, CaseIterable, Identifiable {
  case focus = "Focus"
  case history = "Stats"
  case reminders = "Reminders"
  var id: Self { self }
  var icon: String {
    switch self {
    case .focus: "timer"
    case .history: "chart.bar"
    case .reminders: "checklist"
    }
  }
}

struct MainView: View {
  @Bindable var store: AppStore

  var body: some View {
    ZStack {
      GlassBackground()
      VStack(spacing: 0) {
        Group {
          switch store.selection ?? .focus {
          case .focus:
            if let id = store.completionSessionID {
              ReflectionView(store: store, sessionID: id).padding(24)
            } else {
              FocusView(store: store)
            }
          case .history: HistoryView(store: store)
          case .reminders: RemindersView(store: store)
          }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
        Rectangle().fill(IntervalTheme.border).frame(height: 1)
        HStack(spacing: 18) {
          ForEach(Destination.allCases) { item in
            Button {
              store.selection = item
            } label: {
              Label(item.rawValue, systemImage: item.icon)
            }
            .buttonStyle(.plain)
            .foregroundStyle((store.selection ?? .focus) == item ? .primary : .secondary)
            .accessibilityAddTraits((store.selection ?? .focus) == item ? .isSelected : [])
          }
          Spacer(minLength: 4)
          SettingsLink {
            Image(systemName: "gearshape").font(.system(size: 15)).frame(width: 28, height: 28)
          }
          .buttonStyle(.plain).help("Settings · ⌘,")
          .accessibilityLabel("Settings")
        }.font(.caption).foregroundStyle(.secondary)
          .padding(.horizontal, 18).frame(height: 46)
      }
    }
    .frame(
      width: store.selection == .history ? 640 : 420,
      height: 520
    )
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
  var body: some View {
    VStack(spacing: 0) {
      ScrollView {
        VStack(spacing: 12) {
          VStack(spacing: 4) {
            Text(store.timer.kind.title).font(.callout).foregroundStyle(.secondary)
            Text(durationString(store.remaining)).font(
              .system(
                size: 68, weight: .light, design: .rounded)
            )
            .monospacedDigit().contentTransition(reduceMotion ? .identity : .numericText())
            .accessibilityLabel(timerAccessibilityLabel)
            if store.timer.status == .paused {
              Text("Paused").font(.caption).foregroundStyle(.secondary)
            }
          }
          ProgressView(value: progress).progressViewStyle(.linear)
            .tint(.white.opacity(0.55)).frame(width: 160)
            .accessibilityLabel("Session progress")
          HStack(spacing: 12) {
            Button(action: store.startOrToggle) {
              Label(primaryTitle, systemImage: primaryIcon)
            }
            .buttonStyle(IntervalPrimaryButton())
          }
          .overlay(alignment: .trailing) { cycleActions.offset(x: 38) }
          messageStack.font(.caption)
        }.padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 16)
          .frame(maxWidth: .infinity)
      }
      .defaultScrollAnchor(.center, for: .alignment)
      .frame(maxHeight: .infinity)
      notesPane.frame(height: 180)
    }
    .alert("Abandon this interval?", isPresented: $confirmingAbandon) {
      Button("Keep Going", role: .cancel) {}
      Button("Abandon", role: .destructive, action: store.abandon)
    } message: {
      Text("Elapsed active time will be kept in Stats.")
    }
  }
  @ViewBuilder private var cycleActions: some View {
    if store.timer.status == .running || store.timer.status == .paused {
      Button {
        confirmingAbandon = true
      } label: {
        Image(systemName: "stop.fill").font(.system(size: 11)).frame(width: 26, height: 26)
      }.buttonStyle(.plain).foregroundStyle(.secondary)
        .accessibilityLabel("Abandon cycle").help("Abandon cycle")
    }
  }
  private var progress: Double {
    guard store.timer.duration > 0 else { return 0 }
    return min(1, max(0, 1 - store.remaining / store.timer.duration))
  }
  private var notesPane: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Notes").font(.caption).foregroundStyle(.secondary)
      WritingArea(
        text: Binding(get: { store.data.scratchpad }, set: store.updateScratchpad),
        placeholder: "Add a note…", label: "Global scratchpad")
    }.padding(.horizontal, 24).padding(.vertical, 14).frame(maxHeight: .infinity)
  }
  @ViewBuilder private var messageStack: some View {
    if let notice = store.inAppNotification {
      Label(notice, systemImage: "bell.fill").foregroundStyle(IntervalTheme.accent)
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
    default: "Start"
    }
  }
  private var primaryIcon: String { store.timer.status == .running ? "pause.fill" : "play.fill" }
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
        Text("Stats").font(.headline)
        Spacer()
        Button("Today") {
          month = store.now
          selectedDay = store.now
          selectedSession = nil
          store.calendarService.show(month: store.now)
        }
        .buttonStyle(.bordered)
      }.padding(.horizontal, 18).frame(height: 48)
      Divider().opacity(0.6)
      HStack(spacing: 0) {
        VStack(spacing: 10) {
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
                .accessibilityLabel(dayAccessibilityLabel(date, sessionCount, eventCount))
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
          daySummary
          if let calendarStatus {
            Label(calendarStatus, systemImage: "calendar.badge.exclamationmark")
              .font(.caption).foregroundStyle(.secondary).frame(
                maxWidth: .infinity, alignment: .leading)
          }
          Spacer(minLength: 0)
        }.padding(14).frame(width: 280).frame(maxHeight: .infinity)
        Rectangle().fill(IntervalTheme.border).frame(width: 1)
        if let id = selectedSession, let session = store.data.sessions.first(where: { $0.id == id })
        {
          VStack(spacing: 0) {
            HStack {
              Button {
                selectedSession = nil
              } label: {
                Label("Back", systemImage: "chevron.left")
              }.buttonStyle(.plain)
              Spacer()
              Text("Session").font(.headline)
              Spacer()
            }.padding(.horizontal, 18).frame(height: 44)
            Divider().opacity(0.6)
            SessionInspector(store: store, session: session)
          }.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          timeline
        }
      }
    }.task { store.calendarService.show(month: month) }
  }
  private var daySummary: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(selectedDay.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
        .font(.caption).foregroundStyle(.secondary)
      Text(summaryText).font(.callout)
    }.frame(maxWidth: .infinity, alignment: .leading)
  }
  private var timeline: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(selectedDay.formatted(.dateTime.weekday(.wide).month(.wide).day().year()))
        .font(.headline).padding(.horizontal, 20).frame(height: 44)
      Divider().opacity(0.6)
      if dayItems.isEmpty {
        Text(emptyStatus).font(.callout).foregroundStyle(.secondary)
          .padding(20).frame(maxWidth: .infinity, alignment: .leading)
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
                }.buttonStyle(.plain)
              }
            }
          }.padding(12)
        }
      }
    }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
  private var summaryText: String {
    "\(daySessions.count) session\(daySessions.count == 1 ? "" : "s") · \(dayCalendarEvents.count) event\(dayCalendarEvents.count == 1 ? "" : "s")"
  }
  private var calendarStatus: String? {
    if !store.data.settings.calendarIntegrationEnabled {
      return "Apple Calendar is disabled."
    }
    if store.calendarService.authorizationState != .fullAccess {
      return "Calendar permission is unavailable."
    }
    if store.data.settings.selectedCalendarIDs.isEmpty {
      return "No calendars are selected."
    }
    return nil
  }
  private var emptyStatus: String {
    "No activity on this day."
  }
  private func sessionCount(on date: Date) -> Int {
    store.data.sessions.count { calendar.isDate($0.endedAt, inSameDayAs: date) }
  }
  private func dayAccessibilityLabel(_ date: Date, _ sessionCount: Int, _ eventCount: Int) -> String
  {
    let sessions = sessionCount == 1 ? "session" : "sessions"
    let events = eventCount == 1 ? "calendar event" : "calendar events"
    return
      "\(date.formatted(date: .complete, time: .omitted)), \(sessionCount) \(sessions), \(eventCount) \(events)"
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
        HStack(spacing: 6) {
          Text(session.kind.title).font(.headline)
          Text(session.outcome.rawValue.capitalized).font(.caption).foregroundStyle(.secondary)
        }
        Text(
          "\(session.startedAt.formatted(date: .omitted, time: .shortened))–\(session.endedAt.formatted(date: .omitted, time: .shortened)) · \(session.isDurationEstimated ? "≈ " : "")\(durationString(session.activeDuration))"
        ).font(.caption).foregroundStyle(.secondary)
        if session.isDurationEstimated {
          Text("Estimated duration").font(.caption).foregroundStyle(.secondary)
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
    VStack(spacing: 22) {
      Spacer(minLength: 0)
      Text("Focus complete").font(.title2.weight(.semibold))
      HStack(spacing: 8) {
        ForEach(SessionFeedback.allCases, id: \.self) { value in
          let selected = feedback.wrappedValue == value
          Button {
            setFeedback(value)
          } label: {
            VStack(spacing: 8) {
              Text(value == .distracted ? "🫠" : value == .neutral ? "😐" : "🎯").font(
                .system(size: 28))
              Text(value.title).font(.caption)
            }.frame(maxWidth: .infinity).padding(.vertical, 14)
              .background(
                selected ? Color.blue.opacity(0.22) : .white.opacity(0.05),
                in: RoundedRectangle(cornerRadius: 12))
          }
          .buttonStyle(.plain).accessibilityLabel(value.title)
          .accessibilityAddTraits(feedback.wrappedValue == value ? .isSelected : [])
        }
      }
      WritingArea(text: journal, placeholder: "Add a thought…", label: "Journal")
        .frame(height: 112)
      Button("Continue") { store.continueAfterReflection() }
        .buttonStyle(IntervalPrimaryButton()).keyboardShortcut(.return, modifiers: .command)
        .help("Continue · ⌘Return")
      Spacer(minLength: 0)
    }
  }
  private func setFeedback(_ value: SessionFeedback) { feedback.wrappedValue = value }
}

private struct WritingArea: View {
  @Binding var text: String
  let placeholder: String
  let label: String
  @FocusState private var isFocused: Bool

  var body: some View {
    TextEditor(text: $text)
      .font(.system(size: 13)).lineSpacing(4)
      .scrollContentBackground(.hidden)
      .focused($isFocused)
      .overlay(alignment: .topLeading) {
        if text.isEmpty {
          Text(placeholder).font(.system(size: 13)).foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .allowsHitTesting(false)
        }
      }
      .padding(8)
      .background(.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
      .overlay {
        RoundedRectangle(cornerRadius: 10)
          .strokeBorder(isFocused ? Color.blue.opacity(0.5) : .white.opacity(0.07), lineWidth: 1)
          .allowsHitTesting(false)
      }
      .accessibilityLabel(label)
  }
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
    }.formStyle(.grouped).scrollContentBackground(.hidden).padding(12)
  }
}

struct MenuBarView: View {
  @Bindable var store: AppStore
  @Environment(\.openWindow) private var openWindow
  @State private var confirmingAbandon = false
  @State private var quickNote = ""
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .center, spacing: 12) {
        VStack(alignment: .leading, spacing: 2) {
          Text(store.timer.kind.title).font(.caption).foregroundStyle(.secondary)
          Text(durationString(store.remaining)).font(
            .system(size: 34, weight: .medium, design: .rounded)
          ).monospacedDigit()
        }
        Spacer()
        HStack(spacing: 8) {
          Button(store.completionSessionID == nil ? primaryTitle : "Review") {
            store.startOrToggle()
            if store.completionSessionID != nil {
              openWindow(id: "main")
              NSApp.activate(ignoringOtherApps: true)
            }
          }.buttonStyle(IntervalPrimaryButton())
          if store.timer.status == .running || store.timer.status == .paused {
            Button {
              confirmingAbandon = true
            } label: {
              Image(systemName: "stop.fill").frame(width: 26, height: 26)
            }.buttonStyle(.plain).accessibilityLabel("Abandon cycle").help("Abandon cycle")
          }
        }
      }
      Divider()
      if let warningReminder {
        VStack(alignment: .leading, spacing: 5) {
          Text("Warning: \(warningReminder.title)").font(.caption.weight(.semibold))
          HStack {
            Button("Snooze 5 min") { store.snoozeReminder(warningReminder.id) }
            Button("Skip") { store.dismissReminder(warningReminder.id) }
          }
        }.frame(maxWidth: .infinity, alignment: .leading)
      } else if let reminder = store.nextReminder {
        VStack(alignment: .leading, spacing: 5) {
          Text("Next: \(reminder.title)").font(.caption.weight(.semibold))
          Text(
            reminder.effectiveDueAt?.formatted(date: .omitted, time: .shortened) ?? "Not scheduled"
          ).font(.caption).foregroundStyle(.secondary)
          Button("Snooze 5 min") { store.snoozeReminder(reminder.id) }
        }.frame(maxWidth: .infinity, alignment: .leading)
      }
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
      Divider()
      HStack(spacing: 12) {
        Button("Open Interval") {
          openWindow(id: "main")
          NSApp.activate(ignoringOtherApps: true)
        }
        SettingsLink { Text("Settings") }
        Spacer()
        Button("Quit") { NSApp.terminate(nil) }
      }
    }.padding(14).frame(width: 320).background(GlassBackground()).tint(IntervalTheme.accent)
      .preferredColorScheme(.dark)
      .accessibilityElement(children: .contain)
      .accessibilityLabel(
        "\(store.timer.kind.title), \(store.timer.status.rawValue), \(spokenDuration(store.remaining)) remaining"
      )
      .alert("Abandon this interval?", isPresented: $confirmingAbandon) {
        Button("Keep Going", role: .cancel) {}
        Button("Abandon", role: .destructive, action: store.abandon)
      } message: {
        Text("Elapsed active time will be kept in Stats.")
      }
  }
  private var primaryTitle: String {
    store.timer.status == .running
      ? "Pause"
      : store.timer.status == .paused
        ? "Resume" : "Start"
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
