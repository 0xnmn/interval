import IntervalCore
import SwiftUI

struct FocusControls: View {
  @Bindable var store: AppStore
  var compact = false
  @State private var confirmingAbandon = false
  @State private var confirmingBreak = false
  private var active: Bool { store.timer.status == .running }
  private var accent: Color {
    (store.timer.kind == .focus ? store.data.settings.focusColor : store.data.settings.breakColor)
      .color
  }

  var body: some View {
    GeometryReader { geometry in
      ScrollView {
        VStack(spacing: 12) {
          if !compact { SessionIdentity(store: store) }
          Spacer(minLength: 8)
          if store.timer.kind == .focus {
            FocusDial(
              remaining: store.remaining, accent: accent,
              diameter: compact ? 150 : min(250, max(180, geometry.size.height - 400)))
          } else {
            Text(store.breakEnded ? "Break ended" : "Taking a break")
              .font(.title3).foregroundStyle(store.breakEnded ? .primary : .secondary)
          }
          Text(store.timerText)
            .font(.system(size: 32, weight: .light, design: .rounded)).monospacedDigit()
          if !store.breakEnded { timeControls }
          intervalActions
          Spacer(minLength: 8)
          if let message = store.inAppNotification ?? store.recoveryMessage {
            Text(message).font(IntervalTheme.body).foregroundStyle(.secondary)
          }
          if let error = store.audioError {
            Label(error, systemImage: "speaker.slash").font(IntervalTheme.body).foregroundStyle(
              .orange)
          }
        }.padding(20).frame(maxWidth: .infinity).frame(minHeight: geometry.size.height)
      }
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      if store.timer.status == .ready {
        Button(action: store.startSession) {
          Text(store.timer.kind == .focus ? "Start session" : "Start break")
            .font(IntervalTheme.heading).frame(maxWidth: .infinity).padding(.vertical, 9)
        }.buttonStyle(.borderedProminent).tint(accent).controlSize(.large)
          .clipShape(Capsule()).padding(.horizontal, 24).padding(.bottom, 20)
      }
    }
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

  private var intervalActions: some View {
    HStack(spacing: 16) {
      if store.timer.kind == .focus {
        Button {
          if active { confirmingBreak = true } else { store.startBreakNow() }
        } label: {
          Label("Break", systemImage: "cup.and.saucer")
        }.help("Start a break now").foregroundStyle(store.data.settings.breakColor.color)
      } else if active || store.breakEnded {
        Button {
          store.endBreak()
        } label: {
          Label("Return to focus", systemImage: "arrow.uturn.backward")
        }.help("Return to focus").foregroundStyle(store.data.settings.focusColor.color)
      }
      Button {
        confirmingAbandon = true
      } label: {
        Label("Abandon", systemImage: "stop")
      }.disabled(!active && !store.breakEnded).help("Abandon interval")
    }.buttonStyle(IntervalIconButton()).foregroundStyle(.primary)
  }

  private var timeControls: some View {
    HStack(spacing: 12) {
      adjustmentButton(direction: -1)
      Group {
        let start = store.timer.startedAt ?? store.now
        let end = store.timer.deadline ?? store.now.addingTimeInterval(store.remaining)
        Text(
          "\(start.formatted(date: .omitted, time: .shortened)) → \(end.formatted(date: .omitted, time: .shortened))"
        )
        .font(IntervalTheme.body).monospacedDigit().foregroundStyle(.secondary)
        .lineLimit(1).minimumScaleFactor(0.85)
        .help("Started \(start.formatted()) · Ends \(end.formatted())")
        .accessibilityLabel(
          "Started \(start.formatted(date: .omitted, time: .shortened)), ends \(end.formatted(date: .omitted, time: .shortened))"
        )
      }.frame(maxWidth: .infinity)
      adjustmentButton(direction: 1)
    }
  }

  private func adjustmentButton(direction: Int) -> some View {
    Button {
      store.adjustCurrentTime(by: Double(direction * 300))
    } label: {
      Image(systemName: direction > 0 ? "plus" : "minus")
    }.buttonStyle(IntervalIconButton())
      .disabled(direction > 0 ? store.timer.duration >= 3_600 : store.remaining <= 60)
      .accessibilityLabel(direction > 0 ? "Add 5 minutes" : "Remove 5 minutes")
      .help(
        direction > 0
          ? "Add 5 minutes · Right-click for more" : "Remove 5 minutes · Right-click for more"
      )
      .contextMenu {
        ForEach([5, 10, 15], id: \.self) { minutes in
          Button("\(direction > 0 ? "+" : "−") \(minutes) minutes") {
            store.adjustCurrentTime(by: Double(direction * minutes * 60))
          }
        }
      }
  }

}

struct UpcomingReminders: View {
  @Bindable var store: AppStore
  var body: some View {
    let reminders = store.data.reminders.filter { $0.isEnabled && $0.effectiveDueAt != nil }
      .sorted { $0.effectiveDueAt! < $1.effectiveDueAt! }
    return VStack(alignment: .leading, spacing: 14) {
      Text("Upcoming reminders").font(IntervalTheme.heading).foregroundStyle(.secondary)
      if reminders.isEmpty {
        Text("No reminders scheduled").font(IntervalTheme.body).foregroundStyle(.secondary)
      }
      ForEach(Array(reminders.prefix(3))) { reminder in
        HStack(spacing: 10) {
          Text(reminder.emoji).font(.system(size: 19)).frame(width: 24)
          Text(reminder.title).font(IntervalTheme.body).lineLimit(1)
          Spacer(minLength: 8)
          Text(reminderStatus(reminder)).font(IntervalTheme.body).monospacedDigit().foregroundStyle(
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

struct FocusDial: View {
  let remaining: TimeInterval
  let accent: Color
  var diameter: CGFloat = 250
  static func fraction(for seconds: TimeInterval) -> Double { min(1, max(0, seconds / 3_600)) }
  private var fraction: Double { Self.fraction(for: remaining) }

  var body: some View {
    ZStack {
      ForEach(0..<60) { tick in
        Capsule().fill(
          tick % 5 == 0 ? Color.primary.opacity(0.5) : Color.primary.opacity(0.15)
        )
        .frame(width: tick % 5 == 0 ? 2 : 1, height: tick % 5 == 0 ? 12 : 6)
        .offset(y: -116).rotationEffect(.degrees(Double(tick) * 6))
      }
      Circle().fill(accent.opacity(0.10)).padding(40)
      ClockSector(fraction: fraction).fill(accent.gradient.opacity(0.7)).padding(40)
      Capsule().fill(accent).frame(width: 5, height: 110)
        .offset(y: -49).rotationEffect(.degrees(fraction * 360))
      Circle().fill(.regularMaterial).frame(width: 30, height: 30)
        .overlay { Circle().fill(.white.opacity(0.65)).padding(5) }
        .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
        .overlay { Circle().strokeBorder(accent.opacity(0.5), lineWidth: 3) }
    }.frame(width: 250, height: 250).scaleEffect(diameter / 250)
      .frame(width: diameter, height: diameter)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("Time remaining").accessibilityValue(spokenDuration(remaining))
  }
}

private struct ClockSector: Shape {
  let fraction: Double
  func path(in rect: CGRect) -> Path {
    Path { path in
      let center = CGPoint(x: rect.midX, y: rect.midY)
      path.move(to: center)
      path.addArc(
        center: center, radius: min(rect.width, rect.height) / 2,
        startAngle: .degrees(-90), endAngle: .degrees(-90 + fraction * 360), clockwise: false)
      path.closeSubpath()
    }
  }
}

struct FocusDayPanel: View {
  @Bindable var store: AppStore
  @State private var selectedSessionID: UUID?
  @State private var selectedDay: Date
  @State private var showsDatePicker = false
  private let calendar = Calendar.autoupdatingCurrent

  init(store: AppStore, selectedDate: Date? = nil) {
    self.store = store
    _selectedDay = State(initialValue: selectedDate ?? store.now)
  }

  var sessions: [SessionRecord] {
    store.data.sessions.filter {
      $0.kind == .focus && calendar.isDate($0.endedAt, inSameDayAs: selectedDay)
    }
  }
  var body: some View {
    ThemedSplitView(isVertical: false, minimumFirst: 110, minimumSecond: 400) {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          Text("To-dos").font(IntervalTheme.heading)
          TodoList(store: store)
          UpcomingReminders(store: store).padding(.top, 12)
        }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
      }.frame(minHeight: 110, idealHeight: 190, maxHeight: .infinity)
    } second: {
      VStack(spacing: 0) {
        VStack(spacing: 12) {
          dateNavigation
          HStack {
            Text("\(Int(sessions.reduce(0) { $0 + $1.activeDuration } / 60))m focus")
            Spacer()
            Text("\(sessions.filter { $0.outcome == .completed }.count) completed")
          }.font(IntervalTheme.body).monospacedDigit().foregroundStyle(.secondary)
        }.padding(16).frame(maxWidth: .infinity)
        DayTimeline(store: store, selectedSessionID: $selectedSessionID, date: selectedDay)
          .id(calendar.startOfDay(for: selectedDay))
          .padding(.horizontal, 16)
      }.frame(minHeight: 400, idealHeight: 440, maxHeight: .infinity)
    }
    .onAppear { store.calendarService.show(month: selectedDay) }
    .onChange(of: calendar.startOfDay(for: store.now)) { old, new in
      if calendar.isDate(selectedDay, inSameDayAs: old) { selectDay(new) }
    }
    .sheet(
      isPresented: Binding(
        get: { selectedSessionID != nil }, set: { if !$0 { selectedSessionID = nil } }
      )
    ) {
      if let session = store.data.sessions.first(where: { $0.id == selectedSessionID }) {
        VStack(spacing: 0) {
          HStack {
            Text("Session").font(IntervalTheme.heading)
            Spacer()
            Button("Done") { selectedSessionID = nil }.keyboardShortcut(.cancelAction)
          }.padding(20)
          SessionInspector(store: store, session: session)
        }.frame(width: 460, height: 500).background(GlassBackground())
      }
    }
  }

  private var dateNavigation: some View {
    VStack(spacing: 8) {
      HStack {
        Button {
          moveDay(-1)
        } label: {
          Image(systemName: "chevron.left")
        }
        .buttonStyle(IntervalIconButton()).help("Previous day").accessibilityLabel("Previous day")
        Button {
          showsDatePicker.toggle()
        } label: {
          Text(
            calendar.isDate(selectedDay, inSameDayAs: store.now)
              ? "Today" : selectedDay.formatted(.dateTime.month(.abbreviated).day())
          )
          .font(IntervalTheme.heading).frame(maxWidth: .infinity)
        }.buttonStyle(.plain)
          .popover(isPresented: $showsDatePicker) {
            VStack {
              DatePicker(
                "Date", selection: Binding(get: { selectedDay }, set: selectDay),
                displayedComponents: .date
              )
              .datePickerStyle(.graphical).labelsHidden()
              Button("Today") {
                selectDay(store.now)
                showsDatePicker = false
              }
            }.padding()
          }
        Button {
          moveDay(1)
        } label: {
          Image(systemName: "chevron.right")
        }
        .buttonStyle(IntervalIconButton()).help("Next day").accessibilityLabel("Next day")
      }
      HStack(spacing: 3) {
        ForEach(weekDates, id: \.self) { day in
          Button {
            selectDay(day)
          } label: {
            VStack(spacing: 3) {
              Text(day.formatted(.dateTime.weekday(.narrow))).foregroundStyle(.secondary)
              Text(day.formatted(.dateTime.day())).font(IntervalTheme.heading)
            }.font(IntervalTheme.body).frame(maxWidth: .infinity).padding(.vertical, 6)
              .background(
                calendar.isDate(day, inSameDayAs: selectedDay)
                  ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.035),
                in: RoundedRectangle(cornerRadius: 7))
          }.buttonStyle(.plain).accessibilityLabel(day.formatted(date: .complete, time: .omitted))
            .accessibilityAddTraits(
              calendar.isDate(day, inSameDayAs: selectedDay) ? .isSelected : [])
        }
      }
    }
  }

  private var weekDates: [Date] {
    let start = calendar.dateInterval(of: .weekOfYear, for: selectedDay)?.start ?? selectedDay
    return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
  }
  private func selectDay(_ date: Date) {
    selectedDay = date
    selectedSessionID = nil
    store.calendarService.show(month: date)
  }
  private func moveDay(_ delta: Int) {
    if let date = calendar.date(byAdding: .day, value: delta, to: selectedDay) { selectDay(date) }
  }

}
