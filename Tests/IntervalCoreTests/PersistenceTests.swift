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
  let timer = TimerState(
    kind: .focus, duration: 60, status: .running,
    startedAt: precise, deadline: precise.addingTimeInterval(60))
  try store.save(PersistedData(activeTimer: timer))
  let loaded = try store.load().activeTimer
  #expect(
    abs((loaded?.startedAt?.timeIntervalSince1970 ?? 0) - precise.timeIntervalSince1970) < 0.000001)
}

@Test func decodedSettingsAreClamped() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = JSONStore(fileURL: directory.appendingPathComponent("state.json"))
  try store.save(
    PersistedData(
      settings: .init(
        focusMinutes: -1, shortBreakMinutes: 0,
        longBreakMinutes: 999, longBreakEvery: 0)))
  let settings = try store.load().settings
  #expect(
    settings
      == .init(focusMinutes: 1, shortBreakMinutes: 1, longBreakMinutes: 90, longBreakEvery: 1))
}

@Test func calendarGridHonorsFirstWeekdayAndLeapYear() {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(secondsFromGMT: 0)!
  calendar.firstWeekday = 2
  let date = calendar.date(from: DateComponents(year: 2024, month: 2, day: 15))!
  let grid = CalendarDates.monthGrid(containing: date, calendar: calendar)
  #expect(grid.compactMap { $0 }.count == 29)
  #expect(grid.count == 35)
}

@Test func ambientSettingsRoundTripAndClampVolume() {
  let value = IntervalSettings(focusSound: .rain, breakSound: .ocean, soundVolume: 2).clamped()
  #expect(value.focusSound == .rain)
  #expect(value.breakSound == .ocean)
  #expect(value.soundVolume == 1)
}

@Test func legacyISOStorageMigratesWithOriginalBackup() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = JSONStore(fileURL: directory.appendingPathComponent("state.json"))
  let legacy = Data(
    """
    {"version":1,"settings":{"focusMinutes":25,"shortBreakMinutes":5,"longBreakMinutes":10,"longBreakEvery":4},
    "scratchpad":"Preserve this","sessions":[{"id":"11111111-1111-1111-1111-111111111111",
    "timerID":"22222222-2222-2222-2222-222222222222","kind":"focus",
    "startedAt":"2026-09-05T10:00:00Z","endedAt":"2026-09-05T10:03:00Z",
    "plannedDuration":1500,"outcome":"abandoned"}],"reminders":[],"completedFocusCount":0}
    """.utf8)
  try legacy.write(to: store.fileURL)
  let loaded = try store.load()
  #expect(loaded.scratchpad == "Preserve this")
  #expect(loaded.sessions[0].activeDuration == 180)
  #expect(loaded.sessions[0].isDurationEstimated)
  #expect(try Data(contentsOf: store.fileURL.appendingPathExtension("pre-migration")) == legacy)
  #expect(try Data(contentsOf: store.fileURL) == legacy)
  try store.save(loaded)
  #expect(try store.load() == loaded)
  #expect(try Data(contentsOf: store.fileURL.appendingPathExtension("pre-migration")) == legacy)
}

@Test func futureVersionRemainsUntouched() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = JSONStore(fileURL: directory.appendingPathComponent("state.json"))
  try store.save(PersistedData(version: 99))
  let original = try Data(contentsOf: store.fileURL)
  #expect(throws: (any Error).self) { try store.load() }
  #expect(try Data(contentsOf: store.fileURL) == original)
  #expect(
    !FileManager.default.fileExists(
      atPath: store.fileURL.appendingPathExtension("pre-migration").path))
}
