import Foundation
import Testing

@testable import IntervalCore

@Test func persistenceRoundTripsVersionedData() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = JSONStore(fileURL: directory.appendingPathComponent("state.json"))
  var value = PersistedData(
    todos: [TodoItem(title: "A thought"), TodoItem(title: "Finished", isCompleted: true)],
    completedFocusCount: 3)
  value.reminders = [Reminder(title: "Review tomorrow")]
  try store.save(value)
  #expect(try store.load() == value)
}

@Test func sessionMetadataRoundTripsAndLegacyDataUsesDefaults() throws {
  let category = SessionCategory(name: "Client")
  let timer = TimerState(
    kind: .focus, duration: 60, title: "Proposal", categoryID: category.id,
    categoryName: category.name)
  let record = SessionRecord(
    timerID: timer.id, kind: .focus, startedAt: .distantPast, endedAt: .distantFuture,
    plannedDuration: 60, activeDuration: 60, outcome: .completed, title: timer.title,
    categoryID: timer.categoryID, categoryName: timer.categoryName)
  let value = PersistedData(
    activeTimer: timer, sessions: [record], categories: [category], sessionTitle: "Proposal",
    selectedCategoryID: category.id)
  #expect(try JSONDecoder().decode(PersistedData.self, from: JSONEncoder().encode(value)) == value)

  let legacy = try JSONDecoder().decode(
    PersistedData.self,
    from: Data(
      #"{"version":1,"settings":{"focusMinutes":25,"shortBreakMinutes":5,"longBreakMinutes":10,"longBreakEvery":4},"sessions":[],"reminders":[],"completedFocusCount":0}"#
        .utf8))
  #expect(legacy.categories.isEmpty)
  #expect(legacy.sessionTitle.isEmpty)
  #expect(legacy.selectedCategoryID == nil)
}

@Test func legacyScratchpadMigratesOnceAndRoundTripsAsTodos() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = JSONStore(fileURL: directory.appendingPathComponent("state.json"))
  try Data(
    #"""
    {"version":1,"settings":{"focusMinutes":25,"shortBreakMinutes":5,"longBreakMinutes":10,"longBreakEvery":4},
    "scratchpad":"  First task  \n\nSecond task\n   ","sessions":[],"reminders":[],"completedFocusCount":0}
    """#.utf8
  ).write(to: store.fileURL)

  let migrated = try store.load()
  #expect(migrated.todos.map(\.title) == ["First task", "Second task"])
  #expect(migrated.todos.allSatisfy { !$0.isCompleted })

  try store.save(migrated)
  let encoded = try #require(
    JSONSerialization.jsonObject(with: Data(contentsOf: store.fileURL)) as? [String: Any])
  #expect(encoded["scratchpad"] == nil)
  #expect((encoded["todos"] as? [[String: Any]])?.count == 2)
  #expect(try store.load() == migrated)
}

@Test func explicitEmptyTodosDoNotRemigrateLegacyScratchpad() throws {
  let json = Data(
    """
    {"version":1,"settings":{"focusMinutes":25,"shortBreakMinutes":5,"longBreakMinutes":10,"longBreakEvery":4},
    "todos":[],"scratchpad":"Do not restore","sessions":[],"reminders":[],"completedFocusCount":0}
    """.utf8)
  let decoded = try JSONDecoder().decode(PersistedData.self, from: json)
  #expect(decoded.todos.isEmpty)
}

@Test func defaultSettingsMatchProductDefaults() {
  let settings = IntervalSettings()
  #expect(settings.focusMinutes == 25)
  #expect(settings.shortBreakMinutes == 5)
  #expect(settings.longBreakMinutes == 10)
  #expect(settings.longBreakEvery == 4)
  #expect(settings.focusColor == .green)
  #expect(settings.breakColor == .blue)
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
  let value = IntervalSettings(
    focusColor: .purple, breakColor: .orange, focusSound: .rain, breakSound: .ocean,
    soundVolume: 2
  ).clamped()
  #expect(value.focusColor == .purple)
  #expect(value.breakColor == .orange)
  #expect(value.focusSound == .rain)
  #expect(value.breakSound == .ocean)
  #expect(value.soundVolume == 1)
}

@Test func phaseColorsRoundTripAndLegacySettingsUseDefaults() throws {
  let settings = IntervalSettings(focusColor: .pink, breakColor: .teal)
  #expect(
    try JSONDecoder().decode(IntervalSettings.self, from: JSONEncoder().encode(settings))
      == settings)

  let legacy = try JSONDecoder().decode(
    IntervalSettings.self,
    from: Data(
      #"{"focusMinutes":25,"shortBreakMinutes":5,"longBreakMinutes":10,"longBreakEvery":4}"#
        .utf8))
  #expect(legacy.focusColor == .green)
  #expect(legacy.breakColor == .blue)
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
  #expect(loaded.todos.map(\.title) == ["Preserve this"])
  #expect(loaded.todos[0].isCompleted == false)
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
