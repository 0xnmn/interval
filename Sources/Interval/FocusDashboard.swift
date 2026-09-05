import IntervalCore
import SwiftUI

struct FocusControls: View {
  @Bindable var store: AppStore
  @State private var confirmingAbandon = false
  @State private var confirmingBreak = false
  private var active: Bool { store.timer.status == .running || store.timer.status == .paused }
  private var accent: Color { store.timer.kind == .focus ? .blue : .teal }
  private var primaryTitle: String {
    store.timer.status == .running ? "Pause" : store.timer.status == .paused ? "Resume" : "Start"
  }

  var body: some View {
    ScrollView {
      VStack(spacing: 24) {
        HStack(spacing: 7) {
          Circle().fill(accent).frame(width: 6, height: 6)
          Text(store.timer.kind.title).font(.callout.weight(.medium))
          if store.timer.status == .paused { Text("· Paused").foregroundStyle(.secondary) }
        }.padding(.top, 8)
        FocusDial(remaining: store.remaining, duration: store.timer.duration, accent: accent)
        HStack(spacing: 20) {
          Button {
            store.adjustCurrentTime(by: -60)
          } label: {
            Image(systemName: "minus").frame(width: 32, height: 32)
              .background(.white.opacity(0.07), in: Circle())
          }.disabled(store.remaining <= 60)
            .help("Reduce by one minute").accessibilityLabel("Reduce by one minute")
          Button(action: store.startOrToggle) {
            Label(
              primaryTitle, systemImage: store.timer.status == .running ? "pause.fill" : "play.fill"
            )
            .frame(minWidth: 74)
          }.buttonStyle(IntervalPrimaryButton())
          Button {
            store.adjustCurrentTime(by: 60)
          } label: {
            Image(systemName: "plus").frame(width: 32, height: 32)
              .background(.white.opacity(0.07), in: Circle())
          }.disabled(store.remaining >= 10_800)
            .help("Add one minute").accessibilityLabel("Add one minute")
        }.buttonStyle(.plain)
        HStack(spacing: 24) {
          Button {
            if active { confirmingBreak = true } else { store.startBreakNow() }
          } label: {
            Label("Break", systemImage: "cup.and.saucer")
          }
          .disabled(store.timer.kind != .focus).help("Start a break now")
          Button {
            confirmingAbandon = true
          } label: {
            Label("Abandon", systemImage: "stop.circle")
          }.disabled(!active)
        }.buttonStyle(.plain).font(.callout).foregroundStyle(.secondary)
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

  private var upcomingReminders: some View {
    let reminders = store.data.reminders.filter { $0.isEnabled && $0.effectiveDueAt != nil }
      .sorted { $0.effectiveDueAt! < $1.effectiveDueAt! }
    return VStack(alignment: .leading, spacing: 14) {
      Divider().padding(.bottom, 2)
      HStack {
        Text("Upcoming").font(.caption.weight(.medium)).foregroundStyle(.secondary)
        Spacer()
        Button {
          store.selection = .reminders
        } label: {
          Image(systemName: "arrow.up.right")
        }.buttonStyle(.plain).help("All reminders").accessibilityLabel("All reminders")
      }
      if reminders.isEmpty {
        Text("No reminders scheduled").font(.caption).foregroundStyle(.secondary)
      }
      ForEach(Array(reminders.prefix(3))) { reminder in
        HStack(spacing: 10) {
          Text(reminder.emoji).font(.system(size: 19)).frame(width: 24)
          Text(reminder.title).font(.callout).lineLimit(1)
          Spacer(minLength: 8)
          Text(reminderStatus(reminder)).font(.caption).foregroundStyle(.secondary)
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
    return remaining <= 0 ? "When idle" : "In \(Int(ceil(remaining / 60)))m"
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
      VStack(spacing: 5) {
        Text(durationString(remaining))
          .font(.system(size: 42, weight: .light, design: .rounded)).monospacedDigit()
        Text("remaining").font(.caption).foregroundStyle(.secondary)
      }
    }.frame(width: 250, height: 250)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("Time remaining").accessibilityValue(spokenDuration(remaining))
  }
}

struct FocusDayPanel: View {
  @Bindable var store: AppStore
  private var sessions: [SessionRecord] {
    store.data.sessions.filter {
      $0.kind == .focus && Calendar.autoupdatingCurrent.isDate($0.endedAt, inSameDayAs: store.now)
    }
  }
  var body: some View {
    GeometryReader { geometry in
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          Text("Notes").font(.title3.weight(.semibold))
          WritingArea(
            text: Binding(get: { store.data.scratchpad }, set: store.updateScratchpad),
            placeholder: "Add a note…", label: "Global scratchpad"
          )
          .frame(height: max(180, geometry.size.height * 0.43))
          Divider()
          HStack {
            Text("Today").font(.headline)
            Spacer()
            Button {
              store.selection = .history
            } label: {
              Image(systemName: "arrow.up.right")
            }.buttonStyle(.plain).help("All stats").accessibilityLabel("All stats")
          }
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
          Divider()
          HStack {
            Text("Calendar").font(.headline)
            Spacer()
            Text(store.now.formatted(.dateTime.month(.abbreviated).day()))
              .font(.caption).foregroundStyle(.secondary)
          }
          calendarAgenda
        }.padding(24)
      }
    }
  }

  @ViewBuilder private var calendarAgenda: some View {
    if !store.calendarService.isEnabled || store.calendarService.authorizationState != .fullAccess {
      SettingsLink { Label("Connect your calendar", systemImage: "calendar.badge.plus") }
        .buttonStyle(.plain).font(.callout).foregroundStyle(.secondary)
    } else if store.calendarService.selectedCalendarIDs.isEmpty {
      SettingsLink { Label("Choose calendars", systemImage: "calendar.badge.plus") }
        .buttonStyle(.plain).font(.callout).foregroundStyle(.secondary)
    } else if store.calendarService.todayEvents.isEmpty {
      Text("No events today").font(.callout).foregroundStyle(.secondary)
    } else {
      ForEach(store.calendarService.todayEvents.sorted { $0.start < $1.start }) { event in
        HStack(alignment: .top, spacing: 12) {
          RoundedRectangle(cornerRadius: 2).fill(.blue.opacity(0.7)).frame(width: 3, height: 32)
          VStack(alignment: .leading, spacing: 4) {
            Text(event.title).font(.callout).lineLimit(2)
            Text(
              event.allDay
                ? "All day"
                : "\(event.start.formatted(date: .omitted, time: .shortened)) – \(event.end.formatted(date: .omitted, time: .shortened))"
            )
            .font(.caption).foregroundStyle(.secondary)
          }
          Spacer(minLength: 0)
        }
      }
    }
  }
}
