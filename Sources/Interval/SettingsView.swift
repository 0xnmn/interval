import AppKit
import IntervalCore
import ServiceManagement
import SwiftUI
import UserNotifications

struct SettingsView: View {
  private struct Destination: Identifiable {
    let id: Int
    let title: String
    let systemImage: String
  }

  private let destinations = [
    Destination(id: 0, title: "Timer", systemImage: "timer"),
    Destination(id: 1, title: "Sound", systemImage: "speaker.wave.2"),
    Destination(id: 2, title: "Calendar", systemImage: "calendar"),
    Destination(id: 3, title: "General", systemImage: "gearshape"),
    Destination(id: 4, title: "Updates", systemImage: "arrow.triangle.2.circlepath"),
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
      VStack(alignment: .leading, spacing: 16) {
        Picker("Settings page", selection: $selectedTab) {
          ForEach(destinations) { destination in
            Label(destination.title, systemImage: destination.systemImage)
              .tag(destination.id)
          }
        }
        .pickerStyle(.segmented)
        .labelsHidden()

        if let error = store.persistenceError ?? store.notificationError {
          Label(error, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.red)
            .padding(.horizontal, 4)
        }

        selectedContent
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      .padding(20)
    }
    .frame(width: 560, height: 450)
    .tint(.accentColor)
    .preferredColorScheme(.dark)
    .task {
      notificationStatus = await store.notifications.status()
    }
  }

  @ViewBuilder private var selectedContent: some View {
    switch selectedTab {
    case 0:
      SettingsPage {
        SettingsSection("Durations") {
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
        SettingsSection("Cadence", divided: true) {
          Stepper(
            "Long break every \(store.data.settings.longBreakEvery) focus completions",
            value: setting(\.longBreakEvery), in: 1...12)
          Text("Continue after feedback to start your break.")
            .font(.caption).foregroundStyle(.secondary)
        }
        SettingsSection("Colors", divided: true) {
          phaseColorPicker("Focus color", selection: phaseColorSetting(\.focusColor))
          phaseColorPicker("Break color", selection: phaseColorSetting(\.breakColor))
        }
      }
    case 1:
      SettingsPage {
        SettingsSection("Ambient sound") {
          HStack {
            Text("Focus")
            Spacer()
            Picker("Focus", selection: soundSetting(\.focusSound)) {
              ForEach(AmbientSound.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            .frame(width: 180)
          }
          HStack {
            Text("Break")
            Spacer()
            Picker("Break", selection: soundSetting(\.breakSound)) {
              ForEach(AmbientSound.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            .frame(width: 180)
          }
          HStack(spacing: 14) {
            Text("Volume")
            Slider(value: volumeSetting, in: 0...1)
              .accessibilityLabel("Volume")
          }
        }
        SettingsSection("Alerts", divided: true) {
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
  private func phaseColorSetting(_ keyPath: WritableKeyPath<IntervalSettings, PhaseColor>)
    -> Binding<
      PhaseColor
    >
  {
    Binding(
      get: { store.data.settings[keyPath: keyPath] },
      set: {
        var value = store.data.settings
        value[keyPath: keyPath] = $0
        store.updateSettings(value)
      })
  }
  private func phaseColorPicker(_ title: String, selection: Binding<PhaseColor>) -> some View {
    HStack {
      Text(title)
      Spacer()
      Picker(title, selection: selection) {
        ForEach(PhaseColor.allCases, id: \.rawValue) { phaseColor in
          Label {
            Text(phaseColor.title)
          } icon: {
            Circle().fill(phaseColor.color).frame(width: 8, height: 8)
          }
          .tag(phaseColor)
        }
      }
      .labelsHidden()
      .frame(width: 140)
    }
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

private struct SettingsPage<Content: View>: View {
  @ViewBuilder let content: Content

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) { content }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, 6)
    }
  }
}

private struct SettingsSection<Content: View>: View {
  let title: String
  let divided: Bool
  @ViewBuilder let content: Content

  init(_ title: String, divided: Bool = false, @ViewBuilder content: () -> Content) {
    self.title = title
    self.divided = divided
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      if divided {
        Divider().overlay(IntervalTheme.border)
          .padding(.bottom, 2)
      }
      Text(title.uppercased())
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
      VStack(alignment: .leading, spacing: 10) { content }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

private struct GeneralSettingsView: View {
  @Bindable var store: AppStore
  @Binding var loginEnabled: Bool
  @Binding var loginMessage: String?
  @Binding var exportMessage: String?
  var body: some View {
    SettingsPage {
      SettingsSection("Startup") {
        Toggle("Launch Interval at login", isOn: Binding(get: { loginEnabled }, set: setLogin))
          .toggleStyle(SwitchToggleStyle(tint: .accentColor)).controlSize(.small)
        if SMAppService.mainApp.status == .requiresApproval {
          Label(
            "Approval is required in System Settings → General → Login Items.",
            systemImage: "exclamationmark.circle")
        }
        if let loginMessage { Text(loginMessage).font(.caption).foregroundStyle(.red) }
      }
      SettingsSection("Local data", divided: true) {
        DisclosureGroup("Storage location") {
          Text(store.storageURL.path(percentEncoded: false))
            .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
        }
        Button("Export Data…", action: exportData)
        if let exportMessage { Text(exportMessage).font(.caption).foregroundStyle(.secondary) }
        Text("Exports local settings and activity; calendar event contents are excluded.")
          .font(.caption).foregroundStyle(.secondary)
      }
      SettingsSection("Privacy", divided: true) {
        Text("No analytics or cloud storage; network access is only for updates.")
      }
    }
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
    SettingsPage {
      SettingsSection("Sparkle updates") {
        Text(store.updates.configurationMessage).foregroundStyle(
          store.updates.isConfigured ? Color.secondary : Color.orange)
        Toggle(
          "Automatically check for updates",
          isOn: Binding(
            get: { store.updates.automaticallyChecks },
            set: { store.updates.automaticallyChecks = $0 })
        )
        .toggleStyle(SwitchToggleStyle(tint: .accentColor)).controlSize(.small)
        .disabled(!store.updates.isConfigured)
        Toggle(
          "Automatically download updates",
          isOn: Binding(
            get: { store.updates.automaticallyDownloads },
            set: { store.updates.automaticallyDownloads = $0 })
        )
        .toggleStyle(SwitchToggleStyle(tint: .accentColor)).controlSize(.small)
        .disabled(!store.updates.isConfigured)
        Button("Check Now") { store.updates.checkNow() }.disabled(!store.updates.isConfigured)
      }
    }
  }
}

private struct CalendarSettingsView: View {
  @Bindable var store: AppStore
  var body: some View {
    SettingsPage {
      SettingsSection("Apple Calendar") {
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
          Toggle(
            "Calendar integration",
            isOn: Binding(
              get: { store.data.settings.calendarIntegrationEnabled },
              set: { enabled in
                if enabled {
                  Task { await store.enableCalendarIntegration() }
                } else {
                  store.disableCalendarIntegration()
                }
              })
          )
          .toggleStyle(SwitchToggleStyle(tint: .accentColor)).controlSize(.small)
          if store.data.settings.calendarIntegrationEnabled {
            if store.calendarService.calendars.isEmpty {
              Text("No calendars are available.").foregroundStyle(.secondary)
            } else {
              ForEach(store.calendarService.calendars) { calendar in
                Toggle(
                  calendar.title,
                  isOn: Binding(
                    get: { store.data.settings.selectedCalendarIDs.contains(calendar.id) },
                    set: { store.setCalendarSelected(calendar.id, selected: $0) })
                )
                .toggleStyle(SwitchToggleStyle(tint: .accentColor)).controlSize(.small)
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
  }

  @ViewBuilder private func accessUnavailable(_ message: String) -> some View {
    Label(message, systemImage: "calendar.badge.exclamationmark").foregroundStyle(.secondary)
    Button("Open Privacy Settings") {
      NSWorkspace.shared.open(
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
    }
  }
}
