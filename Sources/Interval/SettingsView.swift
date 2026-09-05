import SwiftUI
import IntervalCore

struct SettingsView: View {
    @Bindable var store: AppStore
    var body: some View {
        TabView {
            Form {
                Section("Durations") {
                    Stepper("Focus: \(store.data.settings.focusMinutes) minutes", value: setting(\.focusMinutes), in: 1...180)
                    Stepper("Short break: \(store.data.settings.shortBreakMinutes) minutes", value: setting(\.shortBreakMinutes), in: 1...60)
                    Stepper("Long break: \(store.data.settings.longBreakMinutes) minutes", value: setting(\.longBreakMinutes), in: 1...90)
                }
                Section("Cadence") { Stepper("Long break every \(store.data.settings.longBreakEvery) focus completions", value: setting(\.longBreakEvery), in: 1...12) }
            }.formStyle(.grouped).padding().tabItem { Label("Timer", systemImage: "timer") }
        }.frame(width: 480, height: 320).tint(.teal)
    }
    private func setting(_ keyPath: WritableKeyPath<IntervalSettings, Int>) -> Binding<Int> {
        Binding(get: { store.data.settings[keyPath: keyPath] }, set: { value in var settings = store.data.settings; settings[keyPath: keyPath] = value; store.updateSettings(settings) })
    }
}
