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
      HStack(spacing: 0) {
        VStack(spacing: 12) {
          ForEach(Destination.allCases) { item in
            Button {
              store.selection = item
            } label: {
              Image(systemName: item.icon)
                .font(.system(size: 18, weight: .medium)).frame(width: 38, height: 38)
                .background(
                  (store.selection ?? .focus) == item ? .white.opacity(0.10) : .clear,
                  in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .foregroundStyle((store.selection ?? .focus) == item ? .primary : .secondary)
            .help(item.rawValue).accessibilityLabel(item.rawValue)
            .accessibilityAddTraits((store.selection ?? .focus) == item ? .isSelected : [])
          }
          Spacer(minLength: 20)
          SettingsLink {
            Image(systemName: "gearshape").font(.system(size: 18)).frame(width: 38, height: 38)
          }.buttonStyle(.plain).help("Settings · ⌘,").accessibilityLabel("Settings")
        }.padding(.vertical, 20).frame(width: 60).foregroundStyle(.secondary)
        Rectangle().fill(IntervalTheme.border).frame(width: 1)
        Group {
          switch store.selection ?? .focus {
          case .focus:
            if let id = store.completionSessionID {
              ReflectionView(store: store, sessionID: id)
                .frame(maxWidth: 372).padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
              FocusView(store: store)
            }
          case .history: HistoryView(store: store)
          case .reminders: RemindersView(store: store)
          }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
          .safeAreaInset(edge: .bottom, spacing: 0) {
            if store.selection == .history || store.selection == .reminders {
              LiveTimerBar(store: store)
            }
          }
      }
    }
    .frame(
      minWidth: 780, maxWidth: .infinity,
      minHeight: 620, maxHeight: .infinity
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
  var body: some View {
    HStack(spacing: 0) {
      FocusControls(store: store).frame(width: 360)
      Rectangle().fill(IntervalTheme.border).frame(width: 1)
      FocusDayPanel(store: store).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }
}

struct HistoryView: View {
  @Bindable var store: AppStore
  @State private var selectedDay = Date()
  @State private var selectedSession: UUID?
  @State private var categoryFilter: CategoryFilter = .all
  @State private var showsDatePicker = false
  private var calendar: Calendar { .autoupdatingCurrent }
  init(store: AppStore, categoryID: UUID? = nil, selectedDate: Date? = nil) {
    self.store = store
    _selectedDay = State(initialValue: selectedDate ?? store.now)
    _categoryFilter = State(initialValue: categoryID.map(CategoryFilter.category) ?? .all)
  }
  var body: some View {
    VStack(spacing: 0) {
      VStack(spacing: 8) {
        HStack(spacing: 8) {
          Text("Stats").font(.headline)
          Spacer()
          Button {
            selectDay(calendar.date(byAdding: .day, value: -1, to: selectedDay) ?? selectedDay)
          } label: {
            Image(systemName: "chevron.left")
          }
          .buttonStyle(IntervalIconButton()).help("Previous day").accessibilityLabel("Previous day")
          Button {
            showsDatePicker.toggle()
          } label: {
            Label(
              selectedDay.formatted(
                .dateTime.weekday(.abbreviated).month(.abbreviated).day().year()),
              systemImage: "calendar")
          }
          .buttonStyle(.bordered).popover(isPresented: $showsDatePicker) {
            DatePicker("Date", selection: dateSelection, displayedComponents: .date)
              .datePickerStyle(.graphical).labelsHidden().padding()
          }
          Button {
            selectDay(calendar.date(byAdding: .day, value: 1, to: selectedDay) ?? selectedDay)
          } label: {
            Image(systemName: "chevron.right")
          }
          .buttonStyle(IntervalIconButton()).help("Next day").accessibilityLabel("Next day")
          Button("Today") { selectDay(store.now) }.buttonStyle(.bordered)
        }
        HStack(spacing: 6) {
          ForEach(weekDates, id: \.self) { date in
            Button {
              selectDay(date)
            } label: {
              VStack(spacing: 3) {
                Text(date.formatted(.dateTime.weekday(.abbreviated))).font(.caption)
                Text(date.formatted(.dateTime.day())).font(.callout.weight(.semibold))
              }.frame(maxWidth: .infinity).padding(.vertical, 5)
                .background(
                  calendar.isDate(date, inSameDayAs: selectedDay)
                    ? IntervalTheme.accent.opacity(0.22) : .clear,
                  in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
              dayAccessibilityLabel(date, sessionCount(on: date), calendarEventCount(on: date))
            )
            .accessibilityAddTraits(
              calendar.isDate(date, inSameDayAs: selectedDay) ? .isSelected : [])
          }
          Picker("Category", selection: $categoryFilter) {
            ForEach(categoryFilters) { filter in Text(categoryFilterName(filter)).tag(filter) }
          }.labelsHidden().frame(width: 150)
        }
      }.padding(.horizontal, 18).padding(.vertical, 10)
      HStack(spacing: 0) {
        VStack(spacing: 10) {
          ScrollView {
            VStack(alignment: .leading, spacing: 24) {
              daySummary
              categoryBreakdown
              feedbackBreakdown
              if let calendarStatus {
                Label(calendarStatus, systemImage: "calendar.badge.exclamationmark")
                  .font(.caption).foregroundStyle(.secondary).frame(
                    maxWidth: .infinity, alignment: .leading)
              }
            }.frame(maxWidth: .infinity, alignment: .leading)
          }
        }.padding(20).frame(width: 240).frame(maxHeight: .infinity)
        Rectangle().fill(IntervalTheme.border).frame(width: 1)
        if let id = selectedSession, let session = store.data.sessions.first(where: { $0.id == id })
        {
          VStack(spacing: 0) {
            HStack {
              Button {
                selectedSession = nil
              } label: {
                Label("Back", systemImage: "chevron.left")
              }.buttonStyle(IntervalIconButton()).help("Back to timeline")
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
    }.task { store.calendarService.show(month: selectedDay) }
      .onChange(of: categoryFilter) { _, _ in selectedSession = nil }
  }
  private var dateSelection: Binding<Date> {
    Binding(get: { selectedDay }, set: { selectDay($0) })
  }
  private var weekDates: [Date] {
    guard let start = calendar.dateInterval(of: .weekOfYear, for: selectedDay)?.start else {
      return []
    }
    return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
  }
  private var daySummary: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Focus time").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
      Text(durationString(focusDuration)).font(.largeTitle.weight(.light)).monospacedDigit()
      Text("\(completedFocusCount) completed").font(.caption).foregroundStyle(
        .secondary)
    }.frame(maxWidth: .infinity, alignment: .leading)
  }
  private var timeline: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text("Timeline").font(.headline)
        Spacer()
        Text(summaryText).font(.caption).foregroundStyle(.secondary)
      }.padding(.horizontal, 20).frame(height: 44)
      if dayItems.isEmpty {
        Text(emptyStatus).font(.callout).foregroundStyle(.secondary)
          .padding(20).frame(maxWidth: .infinity, alignment: .leading)
      } else {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 10) {
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
    store.data.sessions.filter {
      calendar.isDate($0.endedAt, inSameDayAs: selectedDay) && categoryFilter.matches($0)
    }.sorted { $0.endedAt < $1.endedAt }
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
  private var categoryBreakdown: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Categories").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
      if focusCategoryStats.isEmpty {
        Text("No focus sessions").font(.caption).foregroundStyle(.secondary)
      } else {
        ForEach(focusCategoryStats) { stat in
          VStack(alignment: .leading, spacing: 4) {
            HStack {
              Text(stat.name).font(.callout)
              Spacer()
              Text(durationString(stat.duration)).font(.caption).foregroundStyle(.secondary)
            }
            ProgressView(value: stat.duration, total: max(focusDuration, 1))
              .tint(store.data.settings.focusColor.color)
          }
        }
      }
    }
  }
  private var feedbackBreakdown: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Focus feedback").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
      if focusSessions.isEmpty {
        Text("No feedback yet").font(.caption).foregroundStyle(.secondary)
      } else {
        ForEach(feedbackStats) { stat in
          VStack(spacing: 4) {
            HStack {
              Text(stat.label).font(.callout)
              Spacer()
              Text("\(stat.count)").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            }
            ProgressView(value: Double(stat.count), total: Double(max(focusSessions.count, 1)))
              .tint(stat.count == 0 ? Color.clear : Color.secondary)
              .accessibilityLabel(stat.label)
              .accessibilityValue("\(stat.count) of \(focusSessions.count) focus sessions")
          }
        }
      }
    }
  }
  private var focusSessions: [SessionRecord] { daySessions.filter { $0.kind == .focus } }
  var focusDuration: TimeInterval { focusSessions.reduce(0) { $0 + $1.activeDuration } }
  var completedFocusCount: Int { focusSessions.count { $0.outcome == .completed } }
  var feedbackStats: [FeedbackStat] {
    let counts = Dictionary(grouping: focusSessions) {
      SessionFeedback(rawValue: $0.feedback ?? "")
    }
    return [
      FeedbackStat(id: "focused", label: "🎯 Focused", count: counts[.focused]?.count ?? 0),
      FeedbackStat(id: "neutral", label: "😐 Neutral", count: counts[.neutral]?.count ?? 0),
      FeedbackStat(id: "distracted", label: "🫠 Distracted", count: counts[.distracted]?.count ?? 0),
      FeedbackStat(id: "unrated", label: "— Unrated", count: counts[nil]?.count ?? 0),
    ]
  }
  var focusCategoryStats: [CategoryStat] {
    let grouped = Dictionary(grouping: focusSessions) { $0.categoryID }
    return grouped.map { id, sessions in
      CategoryStat(
        id: id,
        name: categoryName(id: id, savedName: sessions.first?.categoryName),
        duration: sessions.reduce(0) { $0 + $1.activeDuration },
        completedCount: sessions.count { $0.outcome == .completed })
    }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }
  private var categoryFilters: [CategoryFilter] {
    var result: [CategoryFilter] = [.all, .uncategorized]
    result += store.data.categories.map { .category($0.id) }
    let configuredIDs = Set(store.data.categories.map(\.id))
    let deletedIDs = Set(store.data.sessions.compactMap(\.categoryID)).subtracting(configuredIDs)
    result += deletedIDs.sorted {
      categoryName(id: $0, savedName: nil).localizedCaseInsensitiveCompare(
        categoryName(id: $1, savedName: nil)) == .orderedAscending
    }.map { .category($0) }
    return result
  }
  private func categoryFilterName(_ filter: CategoryFilter) -> String {
    switch filter {
    case .all: "All categories"
    case .uncategorized: "Uncategorized"
    case .category(let id): categoryName(id: id, savedName: nil)
    }
  }
  private func categoryName(id: UUID?, savedName: String?) -> String {
    guard let id else { return "Uncategorized" }
    if let current = store.data.categories.first(where: { $0.id == id }) { return current.name }
    return savedName
      ?? store.data.sessions.first(where: { $0.categoryID == id })?.categoryName
      ?? "Deleted category"
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
    store.data.sessions.count {
      calendar.isDate($0.endedAt, inSameDayAs: date) && categoryFilter.matches($0)
    }
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
  private func selectDay(_ date: Date) {
    selectedDay = date
    selectedSession = nil
    store.calendarService.show(month: date)
  }
}

private enum CategoryFilter: Hashable, Identifiable {
  case all
  case uncategorized
  case category(UUID)

  var id: Self { self }
  func matches(_ session: SessionRecord) -> Bool {
    switch self {
    case .all: true
    case .uncategorized: session.categoryID == nil
    case .category(let id): session.categoryID == id
    }
  }
}

struct CategoryStat: Identifiable {
  let id: UUID?
  let name: String
  let duration: TimeInterval
  let completedCount: Int
}

struct FeedbackStat: Identifiable {
  let id: String
  let label: String
  let count: Int
}

enum HistoryItem: Identifiable {
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
  var showsReflection = true
  var body: some View {
    HStack {
      Image(systemName: session.outcome == .completed ? "checkmark.circle.fill" : "xmark.circle")
        .foregroundStyle(session.outcome == .completed ? .teal : .secondary)
      VStack(alignment: .leading) {
        Text(session.title?.nilIfBlank ?? session.kind.title).font(.headline)
        Text(session.categoryName?.nilIfBlank ?? "Uncategorized")
          .font(.caption.weight(.medium)).foregroundStyle(.teal)
        Text(
          "\(session.kind.title) · \(session.outcome.rawValue.capitalized) · \(session.startedAt.formatted(date: .omitted, time: .shortened))–\(session.endedAt.formatted(date: .omitted, time: .shortened)) · \(session.isDurationEstimated ? "≈ " : "")\(durationString(session.activeDuration))"
        ).font(.caption).foregroundStyle(.secondary)
        if session.isDurationEstimated {
          Text("Estimated duration").font(.caption).foregroundStyle(.secondary)
        }
        if showsReflection, let feedback = session.feedback {
          Text(feedback.capitalized).font(.caption)
        }
        if showsReflection, let journal = session.journal?.nilIfBlank {
          Text(journal).font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }
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
                selected ? Color.accentColor.opacity(0.22) : .white.opacity(0.05),
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

struct WritingArea: View {
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
          .strokeBorder(
            isFocused ? Color.accentColor.opacity(0.5) : .white.opacity(0.07), lineWidth: 1
          )
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
        LabeledContent("Title", value: session.title?.nilIfBlank ?? session.kind.title)
        LabeledContent("Category", value: categoryName)
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
  private var categoryName: String {
    guard let id = session.categoryID else { return "Uncategorized" }
    return session.categoryName?.nilIfBlank
      ?? store.data.categories.first(where: { $0.id == id })?.name
      ?? "Deleted category"
  }
}

extension String {
  fileprivate var nilIfBlank: String? {
    let value = trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty ? nil : value
  }
}

struct MenuBarView: View {
  @Bindable var store: AppStore
  @Environment(\.openWindow) private var openWindow
  @State private var confirmingAbandon = false
  @State private var confirmingBreak = false
  @State private var quickTodo = ""
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
          if store.completionSessionID != nil {
            Button {
              store.showFocus()
              openWindow(id: "main")
              NSApp.activate(ignoringOtherApps: true)
            } label: {
              Label("Review", systemImage: "square.and.pencil")
            }
            .help("Review completed focus")
          } else if store.timer.status == .ready {
            Button(action: store.startSession) { Label("Start", systemImage: "play.fill") }
              .help("Start interval")
          } else if store.timer.kind != .focus {
            Button {
              store.endBreak()
            } label: {
              Label("End break", systemImage: "briefcase")
            }
            .foregroundStyle(store.data.settings.focusColor.color).help(
              "End break · Return to focus")
          } else {
            Button {
              confirmingBreak = true
            } label: {
              Label("Break", systemImage: "cup.and.saucer")
            }
            .foregroundStyle(store.data.settings.breakColor.color).help("Start a break")
          }
          if store.timer.status == .running {
            Button {
              confirmingAbandon = true
            } label: {
              Label("Abandon", systemImage: "stop")
            }.help("Abandon interval")
          }
        }.buttonStyle(IntervalIconButton())
      }
      if store.timer.status == .running, let start = store.timer.startedAt,
        let end = store.timer.deadline
      {
        Text(
          "\(start.formatted(date: .omitted, time: .shortened)) → \(end.formatted(date: .omitted, time: .shortened))"
        )
        .font(.callout).foregroundStyle(.secondary).monospacedDigit()
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
        TextField("Add a to-do…", text: $quickTodo).onSubmit {
          store.addTodo(quickTodo)
          quickTodo = ""
        }
        Button("Add") {
          store.addTodo(quickTodo)
          quickTodo = ""
        }.disabled(quickTodo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
      .alert("Start a break now?", isPresented: $confirmingBreak) {
        Button("Keep Focusing", role: .cancel) {}
        Button("Start Break") { store.startBreakNow() }
      } message: {
        Text("This unfinished focus session will be saved as abandoned. Your focus time is kept.")
      }
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
