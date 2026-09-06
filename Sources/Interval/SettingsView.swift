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
      HStack(spacing: 0) {
        List(
          selection: Binding<Int?>(
            get: { selectedTab }, set: { if let tab = $0 { selectedTab = tab } })
        ) {
          ForEach(destinations) { destination in
            Label(destination.title, systemImage: destination.systemImage)
              .font(.system(size: 14))
              .frame(height: 28)
              .tag(destination.id)
          }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .accessibilityLabel("Settings pages")
        .frame(width: 140)
        .background(.ultraThinMaterial.opacity(0.35))

        VStack(alignment: .leading, spacing: 12) {
          Text(destinations.first(where: { $0.id == selectedTab })?.title ?? "Settings")
            .font(.title2.weight(.semibold))

          if let error = store.persistenceError ?? store.notificationError {
            Label(error, systemImage: "exclamationmark.triangle.fill")
              .font(.system(size: 14))
              .foregroundStyle(.red)
          }

          selectedContent
            .font(.system(size: 14))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(18)
      }
    }
    .frame(width: 560, height: 450)
    .tint(.accentColor)
    .task {
      notificationStatus = await store.notifications.status()
    }
  }

  @ViewBuilder private var selectedContent: some View {
    switch selectedTab {
    case 0:
      SettingsPage {
        SettingsSection("Durations") {
          minuteRow("Focus", value: setting(\.focusMinutes), range: 1...60)
          minuteRow("Short break", value: setting(\.shortBreakMinutes), range: 1...60)
          minuteRow("Long break", value: setting(\.longBreakMinutes), range: 1...60)
        }
        SettingsSection("Cadence") {
          SettingsRow("Long break") {
            HStack(spacing: 7) {
              Text("Every \(store.data.settings.longBreakEvery) sessions")
                .monospacedDigit()
              Stepper("Long break cadence", value: setting(\.longBreakEvery), in: 1...12)
                .labelsHidden()
            }
          }
          Text("Continue from feedback to begin your break.")
            .font(.system(size: 14)).foregroundStyle(.secondary)
        }
        SettingsSection("Colors") {
          phaseColorPicker("Focus color", selection: phaseColorSetting(\.focusColor))
          phaseColorPicker("Break color", selection: phaseColorSetting(\.breakColor))
        }
      }
    case 1:
      SettingsPage {
        SettingsSection("Ambient sound") {
          SettingsRow("Focus") {
            Picker("Focus", selection: soundSetting(\.focusSound)) {
              ForEach(AmbientSound.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .labelsHidden()
          }
          SettingsRow("Break") {
            Picker("Break", selection: soundSetting(\.breakSound)) {
              ForEach(AmbientSound.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .labelsHidden()
          }
          SettingsRow("Volume") {
            HStack(spacing: 8) {
              Slider(value: volumeSetting, in: 0...1)
                .accessibilityLabel("Volume")
              Text("\(Int(store.data.settings.soundVolume * 100))%")
                .monospacedDigit()
                .frame(width: 34, alignment: .trailing)
                .accessibilityHidden(true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityValue("\(Int(store.data.settings.soundVolume * 100)) percent")
          }
        }
        SettingsSection("Alerts") {
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
    SettingsRow(title) {
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
    }
  }
  private func minuteRow(_ title: String, value: Binding<Int>, range: ClosedRange<Int>)
    -> some View
  {
    SettingsRow(title) {
      HStack(spacing: 7) {
        Text("\(value.wrappedValue) min")
          .monospacedDigit()
          .frame(maxWidth: .infinity, alignment: .trailing)
        Stepper("\(title) duration", value: value, in: range)
          .labelsHidden()
          .accessibilityValue("\(value.wrappedValue) minutes")
      }
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
      VStack(alignment: .leading, spacing: 18) { content }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, 6)
    }
  }
}

private struct SettingsSection<Content: View>: View {
  let title: String
  @ViewBuilder let content: Content

  init(_ title: String, @ViewBuilder content: () -> Content) {
    self.title = title
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(title)
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(.secondary)
      VStack(alignment: .leading, spacing: 10) { content }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

private struct SettingsRow<Control: View>: View {
  let title: String
  @ViewBuilder let control: Control

  init(_ title: String, @ViewBuilder control: () -> Control) {
    self.title = title
    self.control = control()
  }

  var body: some View {
    HStack(spacing: 12) {
      Text(title)
      Spacer(minLength: 8)
      control
        .frame(width: 140, alignment: .trailing)
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
      SettingsSection("Appearance") {
        Picker(
          "Appearance",
          selection: Binding(
            get: { store.data.settings.appearance },
            set: {
              var settings = store.data.settings
              settings.appearance = $0
              store.updateSettings(settings)
            }
          )
        ) {
          ForEach(AppAppearance.allCases, id: \.self) { appearance in
            Text(appearance.title).tag(appearance)
          }
        }
        .pickerStyle(.segmented).labelsHidden()
      }
      SettingsSection("Startup") {
        Toggle(isOn: Binding(get: { loginEnabled }, set: setLogin)) {
          Text("Launch at login").frame(maxWidth: .infinity, alignment: .leading)
        }.toggleStyle(SwitchToggleStyle(tint: .accentColor)).controlSize(.small)
        if SMAppService.mainApp.status == .requiresApproval {
          Label(
            "Approval is required in System Settings → General → Login Items.",
            systemImage: "exclamationmark.circle")
        }
        if let loginMessage { Text(loginMessage).font(.system(size: 14)).foregroundStyle(.red) }
      }
      SettingsSection("Local data") {
        DisclosureGroup("Storage location") {
          Text(store.storageURL.path(percentEncoded: false))
            .font(.system(size: 14))
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
        }
        Button("Export Data…", action: exportData)
        if let exportMessage {
          Text(exportMessage).font(.system(size: 14)).foregroundStyle(.secondary)
        }
        Text("Exports local settings and activity; calendar event contents are excluded.")
          .font(.system(size: 14)).foregroundStyle(.secondary)
      }
      SettingsSection("Privacy") {
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
      SettingsSection(store.updates.isConfigured ? "Updates" : "Updates unavailable") {
        Text(store.updates.configurationMessage)
          .font(.system(size: 14))
          .foregroundStyle(store.updates.isConfigured ? Color.secondary : Color.orange)
        Toggle(
          isOn: Binding(
            get: { store.updates.automaticallyChecks },
            set: { store.updates.automaticallyChecks = $0 })
        ) {
          Text("Check automatically").frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(SwitchToggleStyle(tint: .accentColor)).controlSize(.small)
        .disabled(!store.updates.isConfigured)
        Toggle(
          isOn: Binding(
            get: { store.updates.automaticallyDownloads },
            set: { store.updates.automaticallyDownloads = $0 })
        ) {
          Text("Download automatically").frame(maxWidth: .infinity, alignment: .leading)
        }
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
          Text("Connect Calendar to show events and suppress reminders during meetings.")
            .foregroundStyle(.secondary)
          Button("Enable Calendar Integration") { Task { await store.enableCalendarIntegration() } }
            .buttonStyle(.borderedProminent)
          Text(
            "macOS calls this Full Access. Interval only reads selected calendars and never changes events."
          )
          .font(.system(size: 14)).foregroundStyle(.secondary)
        case .fullAccess:
          Toggle(
            isOn: Binding(
              get: { store.data.settings.calendarIntegrationEnabled },
              set: { enabled in
                if enabled {
                  Task { await store.enableCalendarIntegration() }
                } else {
                  store.disableCalendarIntegration()
                }
              })
          ) {
            Text("Calendar integration").frame(maxWidth: .infinity, alignment: .leading)
          }
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
                .toggleStyle(.checkbox)
                .controlSize(.small)
                .padding(.leading, 18)
              }
              if store.data.settings.selectedCalendarIDs.isEmpty {
                Text("No calendars selected. No events will be displayed or suppress reminders.")
                  .font(.system(size: 14)).foregroundStyle(.secondary)
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
