import Foundation
import Testing
@testable import IntervalCore

@Test func persistenceRoundTripsVersionedData() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = JSONStore(fileURL: directory.appendingPathComponent("state.json"))
    var value = PersistedData(scratchpad: "A thought", completedFocusCount: 3)
    value.reminders = [Reminder(title: "Review tomorrow")]
    try store.save(value)
    #expect(try store.load() == value)
}

@Test func defaultSettingsMatchProductDefaults() {
    let settings = IntervalSettings()
    #expect(settings.focusMinutes == 25)
    #expect(settings.shortBreakMinutes == 5)
    #expect(settings.longBreakMinutes == 10)
    #expect(settings.longBreakEvery == 4)
}

@Test func persistencePreservesSubsecondDates() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = JSONStore(fileURL: directory.appendingPathComponent("state.json"))
    let precise = Date(timeIntervalSince1970: 1_800_000_000.123456)
    let timer = TimerState(kind: .focus, duration: 60, status: .running,
                           startedAt: precise, deadline: precise.addingTimeInterval(60))
    try store.save(PersistedData(activeTimer: timer))
    let loaded = try store.load().activeTimer
    #expect(abs((loaded?.startedAt?.timeIntervalSince1970 ?? 0) - precise.timeIntervalSince1970) < 0.000001)
}

@Test func decodedSettingsAreClamped() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = JSONStore(fileURL: directory.appendingPathComponent("state.json"))
    try store.save(PersistedData(settings: .init(focusMinutes: -1, shortBreakMinutes: 0,
                                                  longBreakMinutes: 999, longBreakEvery: 0)))
    let settings = try store.load().settings
    #expect(settings == .init(focusMinutes: 1, shortBreakMinutes: 1, longBreakMinutes: 90, longBreakEvery: 1))
}
