import Foundation

/// Today's numbers for the dashboard. Reset at midnight.
public struct DailyStats: Codable, Equatable, Sendable {
    public var date: LocalDate
    public var nudges: Int
    public var activeSeconds: Double
    public var lastNudge: Date?

    public init(date: LocalDate, nudges: Int = 0, activeSeconds: Double = 0, lastNudge: Date? = nil) {
        self.date = date
        self.nudges = nudges
        self.activeSeconds = activeSeconds
        self.lastNudge = lastNudge
    }

    enum CodingKeys: String, CodingKey {
        case date, nudges, activeSeconds, lastNudge
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // A file without a readable date is treated as another day's stats and replaced.
        date = container.leniently(.date, default: LocalDate(julianDay: 0))
        nudges = container.leniently(.nudges, default: 0)
        activeSeconds = container.leniently(.activeSeconds, default: 0)
        lastNudge = container.leniently(.lastNudge, default: nil)
    }
}

/// Reads and writes settings and stats as JSON. Writes are atomic; a corrupt file is set aside as ".broken".
public struct SettingsStore: Sendable {
    public let folder: URL

    public init(folder: URL? = nil) {
        self.folder = folder ?? SettingsStore.defaultFolder
    }

    /// ~/Library/Application Support/KeepGreen on the Mac.
    public static var defaultFolder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("KeepGreen", isDirectory: true)
    }

    public var settingsURL: URL { folder.appendingPathComponent("settings.json") }

    public var statsURL: URL { folder.appendingPathComponent("stats.json") }

    public var hasSavedSettings: Bool { FileManager.default.fileExists(atPath: settingsURL.path) }

    public func loadSettings(today: LocalDate) -> AppSettings {
        var settings = read(AppSettings.self, from: settingsURL) ?? AppSettings()
        settings.normalize(today: today)
        return settings
    }

    public func saveSettings(_ settings: AppSettings) throws {
        try write(settings, to: settingsURL)
    }

    public func loadStats(today: LocalDate) -> DailyStats {
        if let stats = read(DailyStats.self, from: statsURL), stats.date == today {
            return stats
        }
        return DailyStats(date: today)
    }

    public func saveStats(_ stats: DailyStats) throws {
        try write(stats, to: statsURL)
    }

    private func read<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            // Keep the broken file for inspection and start fresh rather than refuse to start.
            let broken = url.appendingPathExtension("broken")
            try? FileManager.default.removeItem(at: broken)
            try? FileManager.default.copyItem(at: url, to: broken)
            return nil
        }
    }

    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(value).write(to: url, options: .atomic)
    }
}
