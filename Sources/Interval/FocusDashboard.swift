import IntervalCore
import SwiftUI

struct FocusControls: View {
  @Bindable var store: AppStore
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var compact = false
  var showsDial = true
  var isNotch = false
  @State private var confirmingAbandon = false
  @State private var confirmingBreak = false
  private var active: Bool { store.timer.status == .running }
  private var accent: Color { .accentColor }

  var body: some View {
    GeometryReader { geometry in
      ScrollView {
        VStack(spacing: isNotch ? 8 : 12) {
          if !compact && store.timer.kind == .focus { SessionIdentity(store: store) }
          if !isNotch { Spacer(minLength: 8) }
          if store.timer.kind == .focus && showsDial {
            FocusDial(
              remaining: store.remaining, accent: accent,
              diameter: compact ? 150 : min(250, max(180, geometry.size.height - 400)))
          } else if store.timer.kind != .focus && !isNotch {
            Image(systemName: "figure.mind.and.body")
              .font(.system(size: compact ? 28 : 40, weight: .light))
              .foregroundStyle(.secondary).padding(.bottom, 8)
            Text(store.breakEnded ? "Break Ended" : "Taking a Break")
              .font(.title2.weight(.medium)).foregroundStyle(.primary)
          }
          HStack {
            if isNotch && !store.breakEnded { adjustmentButton(direction: -1) }
            Text(store.timerText)
              .font(
                .system(
                  size: store.timer.kind != .focus && !compact && !isNotch ? 56 : 36,
                  weight: .regular)
              ).monospacedDigit()
              .lineLimit(1).minimumScaleFactor(0.65)
              .frame(maxWidth: isNotch ? .infinity : nil)
              .accessibilityLabel(
                store.breakEnded ? "Time beyond scheduled break" : "Time remaining"
              )
              .accessibilityValue(spokenDuration(store.displayedTime))
              .help(
                store.breakEnded
                  ? "Extra break time. Resume focus when you’re ready." : "Time remaining")
            if isNotch && !store.breakEnded { adjustmentButton(direction: 1) }
          }
          if !store.breakEnded && !isNotch {
            timeControls.frame(maxWidth: store.timer.kind == .focus ? .infinity : 300)
          }
          if !isNotch || store.timer.status != .ready {
            intervalActions.padding(.top, store.timer.kind != .focus && !isNotch ? 12 : 0)
          }
          if !isNotch { Spacer(minLength: 8) }
          if !isNotch, let message = store.inAppNotification ?? store.recoveryMessage {
            Text(message).font(IntervalTheme.body).foregroundStyle(.secondary)
          }
          if let error = store.audioError {
            Label(error, systemImage: "speaker.slash").font(IntervalTheme.body).foregroundStyle(
              .orange)
          }
        }.padding(isNotch ? 0 : 20).frame(maxWidth: .infinity).frame(
          minHeight: geometry.size.height
        )
        .animation(reduceMotion ? nil : IntervalMotion.selection, value: store.timer.kind)
        .animation(reduceMotion ? nil : IntervalMotion.selection, value: store.breakEnded)
      }
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      if store.timer.status == .ready && store.timer.kind == .focus {
        Button(action: store.startSession) {
          Text("Start Session")
            .font(IntervalTheme.heading).frame(maxWidth: .infinity).padding(.vertical, 9)
        }.buttonStyle(IntervalPrimaryButton())
          .help(
            "Start focusing. A break starts automatically when focus ends; reflection is optional. · ⌘⇧S"
          )
          .padding(.horizontal, isNotch ? 0 : 24).padding(
            .bottom, isNotch ? 0 : 20)
      } else if store.timer.status == .ready {
        Button(action: store.startSession) {
          Text("Start Break")
        }.buttonStyle(IntervalPrimaryButton()).help("Start break · ⌘⇧S")
      }
    }
    .alert("Start a break now?", isPresented: $confirmingBreak) {
      Button("Keep Focusing", role: .cancel) {}
      Button("Start Break") { store.startBreakNow() }
    } message: {
      Text("This unfinished focus session will be saved as abandoned. Your focus time is kept.")
    }
    .alert(store.abandonTitle, isPresented: $confirmingAbandon) {
      Button("Keep Going", role: .cancel) {}
      Button("Abandon", role: .destructive, action: store.abandon)
    } message: {
      Text("Elapsed time will remain in Stats.")
    }
  }

  private var intervalActions: some View {
    HStack(spacing: 16) {
      if store.timer.kind == .focus {
        Button {
          if active { confirmingBreak = true } else { store.startBreakNow() }
        } label: {
          Label("Take a Break", systemImage: "figure.mind.and.body")
        }.buttonStyle(IntervalIconButton()).help("Start a break now")
      } else if active || store.breakEnded {
        Button {
          store.endBreak()
        } label: {
          Text("Resume Focus")
        }.buttonStyle(IntervalPrimaryButton()).help("Resume focus")
      }
      if active || store.breakEnded {
        Button {
          confirmingAbandon = true
        } label: {
          Label("Abandon", systemImage: "stop")
        }.help(store.timer.kind == .focus ? "Abandon focus session · ⌘⇧X" : "Abandon break · ⌘⇧X")
      }
    }.buttonStyle(IntervalIconButton()).foregroundStyle(.primary)
  }

  private var timeControls: some View {
    HStack(spacing: 12) {
      adjustmentButton(direction: -1)
      Group {
        if let start = store.timer.startedAt, let end = store.timer.deadline {
          Text(
            "\(start.formatted(date: .omitted, time: .shortened)) → \(end.formatted(date: .omitted, time: .shortened))"
          )
          .font(IntervalTheme.body).monospacedDigit().foregroundStyle(.secondary)
          .lineLimit(1).minimumScaleFactor(0.85)
          .help("Started \(start.formatted()) · Ends \(end.formatted())")
          .accessibilityLabel(
            "Started \(start.formatted(date: .omitted, time: .shortened)), ends \(end.formatted(date: .omitted, time: .shortened))"
          )
        } else {
          Text("Duration").font(IntervalTheme.body).foregroundStyle(.secondary)
        }
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
          ? "+5 minutes · Right-click for more" : "−5 minutes · Right-click for more"
      )
      .contextMenu {
        TimeAdjustmentChoices(direction: direction) { minutes in
          store.adjustCurrentTime(by: Double(direction * minutes * 60))
        }
      }
  }

}

struct UpcomingReminders: View {
  @Bindable var store: AppStore
  var showsHeading = true
  var maximumCount: Int? = 3
  var body: some View {
    let reminders = store.data.reminders.filter { $0.isEnabled && $0.effectiveDueAt != nil }
      .sorted { $0.effectiveDueAt! < $1.effectiveDueAt! }
    let visibleReminders = maximumCount.map { Array(reminders.prefix($0)) } ?? reminders
    return VStack(alignment: .leading, spacing: 14) {
      if showsHeading {
        Text("Upcoming reminders").font(IntervalTheme.heading).foregroundStyle(.primary)
      }
      if reminders.isEmpty {
        Text("No reminders scheduled").font(IntervalTheme.body).foregroundStyle(.secondary)
      }
      ForEach(visibleReminders) { reminder in
        HStack(spacing: 10) {
          Text(reminder.emoji).font(.system(size: 19)).frame(width: 24)
          Text(reminder.title).font(IntervalTheme.body).lineLimit(1)
          Spacer(minLength: 8)
          Text(reminderStatus(reminder)).font(IntervalTheme.body).monospacedDigit().foregroundStyle(
            .primary)
        }
      }
    }
  }

  func reminderStatus(_ reminder: Reminder) -> String {
    if store.audioInputActivity.isActive { return "Microphone in use" }
    let due = reminder.effectiveDueAt ?? store.now
    let checkAt = max(store.now, due)
    let focusEnd =
      reminder.suppressDuringFocus && store.timer.kind == .focus
        && store.timer.status == .running ? store.timer.deadline : nil
    let eventEnd =
      reminder.suppressDuringCalendar
      ? store.calendarService.todayEvents.filter {
        $0.isEligibleForReminderSuppression && $0.start <= checkAt && $0.end > checkAt
      }.map(\.end).max() : nil
    if let eventEnd, eventEnd >= (focusEnd ?? checkAt) { return "Skipped during event" }
    if let focusEnd, focusEnd > checkAt { return "Skipped during focus" }
    let remaining = due.timeIntervalSince(store.now)
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
      Circle().fill(IntervalTheme.surface).frame(width: 30, height: 30)
        .overlay { Circle().fill(accent.opacity(0.12)).padding(5) }
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
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.openSettings) private var openSettings
  @State private var page: Int?
  @State private var selectedSessionID: UUID?
  private let calendar = Calendar.autoupdatingCurrent

  init(store: AppStore, initialPage: Int = 0) {
    self.store = store
    _page = State(initialValue: initialPage)
  }

  var sessions: [SessionRecord] {
    store.data.sessions.filter {
      $0.kind == .focus && calendar.isDate($0.endedAt, inSameDayAs: store.calendarNow)
    }
  }
  var body: some View {
    ScrollViewReader { proxy in
      VStack(spacing: 0) {
        GeometryReader { geometry in
          ScrollView(.horizontal) {
            HStack(spacing: 0) {
              overview.frame(width: geometry.size.width, height: geometry.size.height).id(0)
              calendarPage.frame(width: geometry.size.width, height: geometry.size.height).id(1)
            }.scrollTargetLayout()
          }
          .scrollTargetBehavior(.paging)
          .scrollPosition(id: $page)
          .scrollIndicators(.hidden)
        }
        HStack(spacing: 10) {
          ForEach(0..<2) { index in
            Button {
              withAnimation(reduceMotion ? nil : IntervalMotion.selection) {
                page = index
                proxy.scrollTo(index, anchor: .leading)
              }
            } label: {
              Label(
                index == 0 ? "Overview" : "Calendar",
                systemImage: index == 0 ? "square.grid.2x2" : "calendar"
              )
              .font(IntervalTheme.body).padding(.horizontal, 14).padding(.vertical, 9)
            }
            .buttonStyle(IntervalSelectionButton(selected: (page ?? 0) == index))
            .accessibilityAddTraits((page ?? 0) == index ? .isSelected : [])
          }
        }.padding(12)
      }.frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
          await Task.yield()
          proxy.scrollTo(page ?? 0, anchor: .leading)
        }
    }
  }

  var upcomingEvents: [CalendarEventSnapshot] {
    store.calendarService.todayEvents.filter { !$0.allDay && $0.end > store.calendarNow }
      .sorted { $0.start < $1.start }
  }

  private var calendarUnavailable: Bool {
    !store.data.settings.calendarIntegrationEnabled
      || store.calendarService.authorizationState != .fullAccess
      || store.data.settings.selectedCalendarIDs.isEmpty
  }

  private var calendarAccess: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Connect a calendar to see your events.").font(IntervalTheme.body).foregroundStyle(
        .secondary)
      Button("Calendar Settings…") {
        store.requestedSettingsTab = 2
        openSettings()
      }.buttonStyle(IntervalPrimaryButton())
    }
  }

  private var calendarPage: some View {
    VStack(alignment: .leading, spacing: 16) {
      VStack(alignment: .leading, spacing: 6) {
        Text("Today’s Calendar").font(IntervalTheme.heading)
        Text(store.calendarNow.formatted(date: .complete, time: .omitted))
          .font(IntervalTheme.body).foregroundStyle(.secondary)
      }.padding(.horizontal, 20).padding(.top, 20)
      if calendarUnavailable {
        calendarAccess.padding(.horizontal, 20)
        Spacer()
      } else {
        DayTimeline(
          store: store, selectedSessionID: $selectedSessionID, date: store.calendarNow,
          sessionFilter: { _ in false })
      }
    }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var overview: some View {
    VStack(spacing: 0) {
      VStack(alignment: .leading, spacing: 12) {
        Text("Today").font(IntervalTheme.heading).foregroundStyle(.primary)
        HStack {
          Text("\(Int(sessions.reduce(0) { $0 + $1.activeDuration } / 60))m focus")
          Spacer()
          Text("\(sessions.filter { $0.outcome == .completed }.count) completed")
        }.font(IntervalTheme.body).monospacedDigit().foregroundStyle(.secondary)
      }
      .padding(20).frame(maxWidth: .infinity, alignment: .leading)

      ThemedSplitView(isVertical: false, minimumFirst: 140, minimumSecond: 230) {
        VStack(alignment: .leading, spacing: 12) {
          Text("To-dos").font(IntervalTheme.heading).foregroundStyle(.primary)
            .padding(.horizontal, 20).padding(.top, 16)
          ScrollView {
            TodoList(store: store)
              .padding(.horizontal, 20).padding(.bottom, 20)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
        .frame(minHeight: 140, idealHeight: 240, maxHeight: .infinity).clipped()
      } second: {
        ScrollView {
          VStack(alignment: .leading, spacing: 24) {
            UpcomingReminders(store: store, maximumCount: nil)
            VStack(alignment: .leading, spacing: 12) {
              Text("Upcoming events").font(IntervalTheme.heading)
              if calendarUnavailable {
                calendarAccess
              } else if upcomingEvents.isEmpty {
                Text("No more events today").font(IntervalTheme.body).foregroundStyle(.secondary)
              } else {
                ForEach(upcomingEvents) { event in
                  HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "calendar").foregroundStyle(.secondary)
                    Text(event.title).lineLimit(2)
                    Spacer(minLength: 8)
                    Text(
                      event.start <= store.calendarNow
                        ? "Now" : event.start.formatted(date: .omitted, time: .shortened)
                    )
                    .monospacedDigit().foregroundStyle(.secondary)
                  }.font(IntervalTheme.body)
                }
              }
            }
          }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 230, idealHeight: 280, maxHeight: .infinity).clipped()
      }
    }.frame(maxWidth: .infinity, maxHeight: .infinity)
  }

}
