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
  private var accent: Color {
    (store.timer.kind == .focus ? store.data.settings.focusColor : store.data.settings.breakColor)
      .color
  }

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
            Text(store.breakEnded ? "Break ended" : "Taking a break")
              .font(.title3).foregroundStyle(store.breakEnded ? .primary : .secondary)
          }
          HStack {
            if isNotch && !store.breakEnded { adjustmentButton(direction: -1) }
            Text(store.timerText)
              .font(.system(size: 36, weight: .regular)).monospacedDigit()
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
          if !store.breakEnded && !isNotch { timeControls }
          if !isNotch || store.timer.status != .ready { intervalActions }
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
          Text("Start session")
            .font(IntervalTheme.heading).frame(maxWidth: .infinity).padding(.vertical, 9)
        }.buttonStyle(IntervalPrimaryButton())
          .help(
            "Start focusing. A break starts automatically when focus ends; reflection is optional. · ⌘⇧S"
          )
          .padding(.horizontal, isNotch ? 0 : 24).padding(
            .bottom, isNotch ? 0 : 20)
      } else if store.timer.status == .ready {
        Button(action: store.startSession) {
          Text("Start break")
        }.buttonStyle(IntervalPrimaryButton()).help("Start break · ⌘⇧S")
      }
    }
    .alert("Start a break now?", isPresented: $confirmingBreak) {
      Button("Keep focusing", role: .cancel) {}
      Button("Start break") { store.startBreakNow() }
    } message: {
      Text("This unfinished focus session will be saved as abandoned. Your focus time is kept.")
    }
    .alert(store.abandonTitle, isPresented: $confirmingAbandon) {
      Button("Keep going", role: .cancel) {}
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
          Label("Take a break", systemImage: "cup.and.saucer")
        }.buttonStyle(IntervalIconButton()).help("Start a break now")
          .foregroundStyle(store.data.settings.breakColor.foregroundColor)
      } else if active || store.breakEnded {
        Button {
          store.endBreak()
        } label: {
          Text("Resume focus")
        }.buttonStyle(IntervalPrimaryButton()).help("Resume focus")
          .foregroundStyle(store.data.settings.focusColor.foregroundColor)
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
          ? "Add 5 minutes · Right-click for more" : "Remove 5 minutes · Right-click for more"
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
  private let calendar = Calendar.autoupdatingCurrent

  init(store: AppStore) {
    self.store = store
  }

  var sessions: [SessionRecord] {
    store.data.sessions.filter {
      $0.kind == .focus && calendar.isDate($0.endedAt, inSameDayAs: store.calendarNow)
    }
  }
  var body: some View {
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

      ThemedSplitView(isVertical: false, minimumFirst: 180, minimumSecond: 140) {
        VStack(alignment: .leading, spacing: 12) {
          Text("To-dos").font(IntervalTheme.heading).foregroundStyle(.primary)
            .padding(.horizontal, 20).padding(.top, 16)
          ScrollView {
            TodoList(store: store)
              .padding(.horizontal, 20).padding(.bottom, 20)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
        .frame(minHeight: 180, idealHeight: 280, maxHeight: .infinity).clipped()
      } second: {
        VStack(alignment: .leading, spacing: 12) {
          Text("Upcoming reminders").font(IntervalTheme.heading).foregroundStyle(.primary)
            .padding(.horizontal, 20).padding(.top, 16)
          ScrollView {
            UpcomingReminders(store: store, showsHeading: false, maximumCount: nil)
              .padding(.horizontal, 20).padding(.bottom, 20)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
        .frame(minHeight: 140, idealHeight: 220, maxHeight: .infinity).clipped()
      }
    }.frame(maxWidth: .infinity, maxHeight: .infinity)
  }

}
