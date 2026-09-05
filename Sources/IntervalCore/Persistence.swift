import Foundation

public struct JSONStore: Sendable {
    public let fileURL: URL
    public init(fileURL: URL? = nil) {
        if let fileURL { self.fileURL = fileURL }
        else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.fileURL = base.appendingPathComponent("Interval", isDirectory: true).appendingPathComponent("data-v1.json")
        }
    }

    public func load() throws -> PersistedData {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return PersistedData() }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .secondsSince1970
        var result = try decoder.decode(PersistedData.self, from: data)
        guard result.version == PersistedData.currentVersion else { throw CocoaError(.fileReadCorruptFile) }
        result.settings = result.settings.clamped()
        result.reminders = result.reminders.map { $0.clamped() }
        return result
    }

    public func save(_ value: PersistedData) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .secondsSince1970
        try encoder.encode(value).write(to: fileURL, options: .atomic)
    }
}
