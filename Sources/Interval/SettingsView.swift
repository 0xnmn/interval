import SwiftUI
import IntervalCore
import UserNotifications
import AppKit

struct SettingsView: View {
    @Bindable var store: AppStore
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var selectedTab: Int
    init(store: AppStore, showSound: Bool = false) { self.store = store; _selectedTab = State(initialValue: showSound ? 1 : 0) }
    var body: some View {
        TabView(selection: $selectedTab) {
            Form {
                Section("Durations") {
                    Stepper("Focus: \(store.data.settings.focusMinutes) minutes", value: setting(\.focusMinutes), in: 1...180)
                    Stepper("Short break: \(store.data.settings.shortBreakMinutes) minutes", value: setting(\.shortBreakMinutes), in: 1...60)
                    Stepper("Long break: \(store.data.settings.longBreakMinutes) minutes", value: setting(\.longBreakMinutes), in: 1...90)
                }
                Section("Cadence") { Stepper("Long break every \(store.data.settings.longBreakEvery) focus completions", value: setting(\.longBreakEvery), in: 1...12) }
            }.formStyle(.grouped).padding().tabItem { Label("Timer", systemImage: "timer") }.tag(0)
            Form {
                Section("Ambient sound") {
                    Picker("Focus", selection: soundSetting(\.focusSound)) { ForEach(AmbientSound.allCases, id: \.self) { Text($0.title).tag($0) } }
                    Picker("Break", selection: soundSetting(\.breakSound)) { ForEach(AmbientSound.allCases, id: \.self) { Text($0.title).tag($0) } }
                    Slider(value: volumeSetting, in: 0...1) { Text("Volume") }
                }
                Section("Completions") {
                    if notificationStatus == .authorized { Label("Notifications enabled", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                    else if notificationStatus == .denied { Label("Notifications denied. Interval will show an in-app completion message.", systemImage: "bell.slash"); Button("Open System Settings") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!) } }
                    else { Button("Enable Notifications") { Task {
                        do { _ = try await store.notifications.request(); store.notificationError = nil }
                        catch { store.notificationError = "Couldn’t request notification access: \(error.localizedDescription)" }
                        notificationStatus = await store.notifications.status()
                    } } }
                    if let error = store.notificationError {
                        Label(error, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.red)
                    }
                }
            }.formStyle(.grouped).padding().tabItem { Label("Sound & Alerts", systemImage: "speaker.wave.2") }.tag(1)
        }.frame(width: 500, height: 370).tint(.teal).task { notificationStatus = await store.notifications.status() }
    }
    private func setting(_ keyPath: WritableKeyPath<IntervalSettings, Int>) -> Binding<Int> {
        Binding(get: { store.data.settings[keyPath: keyPath] }, set: { value in var settings = store.data.settings; settings[keyPath: keyPath] = value; store.updateSettings(settings) })
    }
    private func soundSetting(_ keyPath: WritableKeyPath<IntervalSettings, AmbientSound>) -> Binding<AmbientSound> { Binding(get: { store.data.settings[keyPath: keyPath] }, set: { var value = store.data.settings; value[keyPath: keyPath] = $0; store.updateSettings(value) }) }
    private var volumeSetting: Binding<Double> { Binding(get: { store.data.settings.soundVolume }, set: { var value = store.data.settings; value.soundVolume = $0; store.updateSettings(value) }) }
}
