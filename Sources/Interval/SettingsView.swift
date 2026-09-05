import AppKit
import IntervalCore
import ServiceManagement
import SwiftUI
import UserNotifications

struct SettingsView: View {
  private struct Destination: Identifiable {
    let id: Int
    let title: String
    let subtitle: String
    let systemImage: String
  }

  private let destinations = [
    Destination(id: 0, title: "Timer", subtitle: "Durations and cadence", systemImage: "timer"),
    Destination(
      id: 1, title: "Sound & Alerts", subtitle: "Ambient audio and completions",
      systemImage: "speaker.wave.2"),
    Destination(
      id: 2, title: "Calendar", subtitle: "Calendar access and visibility", systemImage: "calendar"),
    Destination(
      id: 3, title: "General", subtitle: "Startup, data, and privacy", systemImage: "gearshape"),
    Destination(
      id: 4, title: "Updates", subtitle: "Automatic update preferences",
      systemImage: "arrow.triangle.2.circlepath"),
  ]

  @Bindable var store: AppStore
  @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
  @State private var selectedTab: Int
  @State private var loginEnabled = SMAppService.mainApp.status == .enabled
  @State private var loginMessage: String?
  @State private var exportMessage: String?
  init(
    store: AppStore, showSound: Bool = false, showCalendar: Bool = false, selectedTab: Int? = nil
  ) {
    self.store = store
    _selectedTab = State(initialValue: selectedTab ?? (showCalendar ? 2 : showSound ? 1 : 0))
  }
  var body: some View {
    ZStack {
      GlassBackground()
      HStack(spacing: 0) {
        sidebar
        Divider().overlay(IntervalTheme.border)
        VStack(alignment: .leading, spacing: 14) {
          sectionHeader
          if let error = store.persistenceError ?? store.notificationError {
            Label(error, systemImage: "exclamationmark.triangle.fill")
              .font(.caption)
              .foregroundStyle(.red)
              .padding(.horizontal, 4)
          }
          selectedContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .intervalPanel()
        }
        .padding(20)
      }
    }
    .frame(width: 760, height: 560)
    .tint(IntervalTheme.accent)
    .preferredColorScheme(.dark)
    .task {
      notificationStatus = await store.notifications.status()
    }
  }

  private var sidebar: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("INTERVAL")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .tracking(1.4)
        .padding(.horizontal, 12)
        .padding(.bottom, 10)

      ForEach(destinations) { destination in
        Button {
          selectedTab = destination.id
        } label: {
          Label(destination.title, systemImage: destination.systemImage)
            .font(.callout.weight(selectedTab == destination.id ? .semibold : .regular))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(selectedTab == destination.id ? Color.primary : Color.secondary)
        .background {
          if selectedTab == destination.id {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
              .fill(IntervalTheme.accent.opacity(0.16))
              .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                  .stroke(IntervalTheme.accent.opacity(0.24))
              }
          }
        }
        .accessibilityAddTraits(selectedTab == destination.id ? .isSelected : [])
      }
      Spacer()
    }
    .padding(14)
    .frame(width: 160)
  }

  private var sectionHeader: some View {
    let destination = destinations.first(where: { $0.id == selectedTab }) ?? destinations[0]
    return VStack(alignment: .leading, spacing: 3) {
      Text(destination.title).font(.title2.weight(.semibold))
      Text(destination.subtitle).font(.callout).foregroundStyle(.secondary)
    }
  }

  @ViewBuilder private var selectedContent: some View {
    switch selectedTab {
    case 0:
      Form {
        Section("Durations") {
          Stepper(
            "Focus: \(store.data.settings.focusMinutes) minutes", value: setting(\.focusMinutes),
            in: 1...180)
          Stepper(
            "Short break: \(store.data.settings.shortBreakMinutes) minutes",
            value: setting(\.shortBreakMinutes), in: 1...60)
          Stepper(
            "Long break: \(store.data.settings.longBreakMinutes) minutes",
            value: setting(\.longBreakMinutes), in: 1...90)
        }
        Section("Cadence") {
          Stepper(
            "Long break every \(store.data.settings.longBreakEvery) focus completions",
            value: setting(\.longBreakEvery), in: 1...12)
          Text("Cadence changes apply to future completions and do not reset the current timer.")
            .font(.caption).foregroundStyle(.secondary)
        }
      }
      .formStyle(.grouped)
      .scrollContentBackground(.hidden)
    case 1:
      Form {
        Section("Ambient sound") {
          Picker("Focus", selection: soundSetting(\.focusSound)) {
            ForEach(AmbientSound.allCases, id: \.self) { Text($0.title).tag($0) }
          }
          Picker("Break", selection: soundSetting(\.breakSound)) {
            ForEach(AmbientSound.allCases, id: \.self) { Text($0.title).tag($0) }
          }
          Slider(value: volumeSetting, in: 0...1) { Text("Volume") }
        }
        Section("Completions") {
          if notificationStatus == .authorized {
            Label("Notifications enabled", systemImage: "checkmark.circle.fill").foregroundStyle(
              .green)
          } else if notificationStatus == .denied {
            Label(
              "Notifications denied. Interval will show an in-app completion message.",
              systemImage: "bell.slash")
            Button("Open System Settings") {
              NSWorkspace.shared.open(
                URL(
                  string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!
              )
            }
          } else {
            Button("Enable Notifications") {
              Task {
                do {
                  _ = try await store.notifications.request()
                  store.notificationError = nil
                } catch {
                  store.notificationError =
                    "Couldn’t request notification access: \(error.localizedDescription)"
                }
                notificationStatus = await store.notifications.status()
              }
            }
          }
        }
      }
      .formStyle(.grouped)
      .scrollContentBackground(.hidden)
    case 2:
      CalendarSettingsView(store: store)
    case 3:
      GeneralSettingsView(
        store: store, loginEnabled: $loginEnabled, loginMessage: $loginMessage,
        exportMessage: $exportMessage)
    case 4:
      UpdatesSettingsView(store: store)
    default:
      EmptyView()
    }
  }
  private func setting(_ keyPath: WritableKeyPath<IntervalSettings, Int>) -> Binding<Int> {
    Binding(
      get: { store.data.settings[keyPath: keyPath] },
      set: { value in
        var settings = store.data.settings
        settings[keyPath: keyPath] = value
        store.updateSettings(settings)
      })
  }
  private func soundSetting(_ keyPath: WritableKeyPath<IntervalSettings, AmbientSound>) -> Binding<
    AmbientSound
  > {
    Binding(
      get: { store.data.settings[keyPath: keyPath] },
      set: {
        var value = store.data.settings
        value[keyPath: keyPath] = $0
        store.updateSettings(value)
      })
  }
  private var volumeSetting: Binding<Double> {
    Binding(
      get: { store.data.settings.soundVolume },
      set: {
        var value = store.data.settings
        value.soundVolume = $0
        store.updateSettings(value)
      })
  }
}

private struct GeneralSettingsView: View {
  @Bindable var store: AppStore
  @Binding var loginEnabled: Bool
  @Binding var loginMessage: String?
  @Binding var exportMessage: String?
  var body: some View {
    Form {
      Section("Startup") {
        Toggle("Launch Interval at login", isOn: Binding(get: { loginEnabled }, set: setLogin))
        if SMAppService.mainApp.status == .requiresApproval {
          Label(
            "Approval is required in System Settings → General → Login Items.",
            systemImage: "exclamationmark.circle")
        }
        if let loginMessage { Text(loginMessage).font(.caption).foregroundStyle(.red) }
      }
      Section("Local data") {
        LabeledContent("Storage", value: store.storageURL.path(percentEncoded: false))
        Button("Export Data…", action: exportData)
        if let exportMessage { Text(exportMessage).font(.caption).foregroundStyle(.secondary) }
        Text(
          "The export contains Interval settings, timer/session history, reminders, reflections, and scratchpad. Calendar event contents are never stored or exported."
        )
        .font(.caption).foregroundStyle(.secondary)
      }
      Section("Privacy") {
        Text(
          "Interval has no analytics and makes no cloud writes. Your data stays in the local file shown above; network access is used only for a configured update feed."
        )
      }
    }
    .formStyle(.grouped)
    .scrollContentBackground(.hidden)
  }
  private func setLogin(_ enabled: Bool) {
    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
      loginEnabled = SMAppService.mainApp.status == .enabled
      loginMessage = nil
    } catch {
      loginEnabled = SMAppService.mainApp.status == .enabled
      loginMessage = error.localizedDescription
    }
  }
  private func exportData() {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = "Interval-data.json"
    panel.allowedContentTypes = [.json]
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      try store.exportData(to: url)
      exportMessage = "Exported to \(url.path(percentEncoded: false))."
    } catch { exportMessage = "Export failed: \(error.localizedDescription)" }
  }
}

private struct UpdatesSettingsView: View {
  @Bindable var store: AppStore
  var body: some View {
    Form {
      Section("Sparkle updates") {
        Text(store.updates.configurationMessage).foregroundStyle(
          store.updates.isConfigured ? Color.secondary : Color.orange)
        Toggle(
          "Automatically check for updates",
          isOn: Binding(
            get: { store.updates.automaticallyChecks },
            set: { store.updates.automaticallyChecks = $0 })
        )
        .disabled(!store.updates.isConfigured)
        Toggle(
          "Automatically download updates",
          isOn: Binding(
            get: { store.updates.automaticallyDownloads },
            set: { store.updates.automaticallyDownloads = $0 })
        )
        .disabled(!store.updates.isConfigured)
        Button("Check Now") { store.updates.checkNow() }.disabled(!store.updates.isConfigured)
      }
    }
    .formStyle(.grouped)
    .scrollContentBackground(.hidden)
  }
}

private struct CalendarSettingsView: View {
  @Bindable var store: AppStore
  var body: some View {
    Form {
      Section("Apple Calendar") {
        switch store.calendarService.authorizationState {
        case .notDetermined:
          Text("Calendar access is off. Interval continues to work without it.").foregroundStyle(
            .secondary)
          Button("Enable Calendar Integration") { Task { await store.enableCalendarIntegration() } }
            .buttonStyle(.borderedProminent)
          Text(
            "macOS calls this Full Access. Interval only reads selected calendars; it never creates, edits, or deletes events."
          )
          .font(.caption).foregroundStyle(.secondary)
        case .fullAccess:
          LabeledContent(
            "Integration",
            value: store.data.settings.calendarIntegrationEnabled ? "Enabled" : "Disabled")
          LabeledContent(
            "Selected calendars", value: "\(store.data.settings.selectedCalendarIDs.count)")
          Toggle(
            "Enable Calendar Integration",
            isOn: Binding(
              get: { store.data.settings.calendarIntegrationEnabled },
              set: { enabled in
                if enabled {
                  Task { await store.enableCalendarIntegration() }
                } else {
                  store.disableCalendarIntegration()
                }
              }))
          if store.data.settings.calendarIntegrationEnabled {
            if store.calendarService.calendars.isEmpty {
              Text("No calendars are available.").foregroundStyle(.secondary)
            } else {
              ForEach(store.calendarService.calendars) { calendar in
                Toggle(
                  calendar.title,
                  isOn: Binding(
                    get: { store.data.settings.selectedCalendarIDs.contains(calendar.id) },
                    set: { store.setCalendarSelected(calendar.id, selected: $0) }))
              }
              if store.data.settings.selectedCalendarIDs.isEmpty {
                Text("No calendars selected. No events will be displayed or suppress reminders.")
                  .font(.caption).foregroundStyle(.secondary)
              }
            }
          }
        case .denied:
          accessUnavailable(
            "Calendar access was denied or revoked. Calendar features are unavailable; the rest of Interval still works."
          )
        case .restricted:
          accessUnavailable(
            "Calendar access is restricted on this Mac. The rest of Interval still works.")
        case .error(let message):
          Label("Calendar access failed: \(message)", systemImage: "exclamationmark.triangle")
            .foregroundStyle(.orange)
        }
      }
    }
    .formStyle(.grouped)
    .scrollContentBackground(.hidden)
  }

  @ViewBuilder private func accessUnavailable(_ message: String) -> some View {
    Label(message, systemImage: "calendar.badge.exclamationmark").foregroundStyle(.secondary)
    Button("Open Privacy Settings") {
      NSWorkspace.shared.open(
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
    }
  }
}
