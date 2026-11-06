import Foundation

/// How KeepGreen tells macOS that someone is at the keyboard.
public enum NudgeStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Declares user activity to the power manager. Needs no permission.
    case declareActivity = "DeclareActivity"

    /// Posts a zero-distance mouse event at the cursor. The cursor never moves. Needs Accessibility access.
    case invisibleMouse = "InvisibleMouse"

    /// Sends nothing at all; only keeps the Mac and screen awake.
    case awakeOnly = "AwakeOnly"

    public var id: String { rawValue }
}

/// Work hours for one day of the week. An end at or before the start runs past midnight.
public struct DaySchedule: Codable, Hashable, Identifiable, Sendable {
    public var day: Weekday
    public var enabled: Bool
    public var start: TimeOfDay
    public var end: TimeOfDay

    public init(day: Weekday, enabled: Bool, start: TimeOfDay = TimeOfDay(8), end: TimeOfDay = TimeOfDay(17)) {
        self.day = day
        self.enabled = enabled
        self.start = start
        self.end = end
    }

    enum CodingKeys: String, CodingKey {
        case day, enabled, start, end
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        day = try container.decode(Weekday.self, forKey: .day)
        enabled = container.leniently(.enabled, default: !day.isWeekend)
        start = container.leniently(.start, default: TimeOfDay(8))
        end = container.leniently(.end, default: TimeOfDay(17))
    }

    public var id: Weekday { day }

    public var dayName: String { day.name }

    /// Length of the work window in minutes. Equal start and end means a full 24 hours.
    public var lengthMinutes: Int {
        let difference = (end.minutesSinceMidnight - start.minutesSinceMidnight + 1440) % 1440
        return difference == 0 ? 1440 : difference
    }

    /// Length of the work window on an ordinary day (without a daylight saving change).
    public var length: TimeInterval { TimeInterval(lengthMinutes * 60) }

    public var lengthText: String { Humanize.duration(length) }
}

/// Everything the user can configure. Saved as JSON; keys missing from older files fall back to their defaults.
public struct AppSettings: Codable, Equatable, Sendable {
    public static let minIntervalSeconds = 15

    // Teams switches to Away after 5 minutes idle; with ±20% variation this still nudges before 4m48s.
    public static let maxIntervalSeconds = 240

    /// Mac app names as the Dock and Activity Monitor show them.
    public static let defaultWatchedApps = "Microsoft Teams, Slack, zoom.us"

    public static let batteryChoices = [10, 15, 20, 25, 30, 40, 50]

    public var isEnabled = true
    public var useSchedule = true
    public var week: [DaySchedule] = AppSettings.defaultWeek()
    public var daysOff: [LocalDate] = []
    public var lunchBreakEnabled = false
    public var lunchStart = TimeOfDay(12, 0)
    public var lunchEnd = TimeOfDay(12, 30)
    public var intervalSeconds = 60
    public var randomizeInterval = true
    public var style: NudgeStyle = .declareActivity
    public var pauseWhenLocked = true
    public var pauseOnBattery = false
    public var pauseOnLowBattery = true
    public var lowBatteryPercent = 15
    public var onlyWhenAppsRunning = false

    /// App names separated by commas, semicolons or new lines, e.g. "Microsoft Teams, Slack".
    public var watchedApps = AppSettings.defaultWatchedApps

    public var notifications = true

    /// Whether the phone remote server is on. Off by default.
    public var remoteEnabled = false

    /// The shared key for paired phones: 32 lowercase hex characters, or nil until the remote is first turned on.
    public var remoteKey: String?

    public init() {}

    enum CodingKeys: String, CodingKey {
        case isEnabled, useSchedule, week, daysOff, lunchBreakEnabled, lunchStart, lunchEnd
        case intervalSeconds, randomizeInterval, style, pauseWhenLocked, pauseOnBattery, pauseOnLowBattery
        case lowBatteryPercent, onlyWhenAppsRunning, watchedApps, notifications, remoteEnabled, remoteKey
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = container.leniently(.isEnabled, default: isEnabled)
        useSchedule = container.leniently(.useSchedule, default: useSchedule)
        week = container.leniently(.week, default: week)
        daysOff = container.leniently(.daysOff, default: daysOff)
        lunchBreakEnabled = container.leniently(.lunchBreakEnabled, default: lunchBreakEnabled)
        lunchStart = container.leniently(.lunchStart, default: lunchStart)
        lunchEnd = container.leniently(.lunchEnd, default: lunchEnd)
        intervalSeconds = container.leniently(.intervalSeconds, default: intervalSeconds)
        randomizeInterval = container.leniently(.randomizeInterval, default: randomizeInterval)
        style = container.leniently(.style, default: style)
        pauseWhenLocked = container.leniently(.pauseWhenLocked, default: pauseWhenLocked)
        pauseOnBattery = container.leniently(.pauseOnBattery, default: pauseOnBattery)
        pauseOnLowBattery = container.leniently(.pauseOnLowBattery, default: pauseOnLowBattery)
        lowBatteryPercent = container.leniently(.lowBatteryPercent, default: lowBatteryPercent)
        onlyWhenAppsRunning = container.leniently(.onlyWhenAppsRunning, default: onlyWhenAppsRunning)
        watchedApps = container.leniently(.watchedApps, default: watchedApps)
        notifications = container.leniently(.notifications, default: notifications)
        remoteEnabled = container.leniently(.remoteEnabled, default: remoteEnabled)
        remoteKey = container.leniently(.remoteKey, default: remoteKey)
    }

    public func day(_ weekday: Weekday) -> DaySchedule? {
        week.first { $0.day == weekday }
    }

    public mutating func updateDay(_ weekday: Weekday, _ change: (inout DaySchedule) -> Void) {
        guard let index = week.firstIndex(where: { $0.day == weekday }) else { return }
        change(&week[index])
    }

    /// The watched app names: trimmed, without ".app" or ".exe", and without duplicates (ignoring case).
    /// Mac app names contain spaces ("Microsoft Teams"), so only commas, semicolons and new lines separate them.
    public func watchedAppNames() -> [String] {
        var seen = Set<String>()
        var names: [String] = []
        for part in watchedApps.components(separatedBy: CharacterSet(charactersIn: ",;\n\r")) {
            var name = part.trimmingCharacters(in: .whitespacesAndNewlines)
            for suffix in [".app", ".exe"] where name.lowercased().hasSuffix(suffix) {
                name = String(name.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
            }
            guard !name.isEmpty, seen.insert(name.lowercased()).inserted else { continue }
            names.append(name)
        }
        return names
    }

    public static func defaultWeek() -> [DaySchedule] {
        Weekday.weekOrder.map { DaySchedule(day: $0, enabled: !$0.isWeekend, start: TimeOfDay(8), end: TimeOfDay(17)) }
    }

    /// Repairs a loaded file: clamps numbers, restores missing days, drops past days off.
    public mutating func normalize(today: LocalDate) {
        intervalSeconds = min(max(intervalSeconds, AppSettings.minIntervalSeconds), AppSettings.maxIntervalSeconds)
        lowBatteryPercent = min(max(lowBatteryPercent, 5), 95)
        lunchStart = lunchStart.roundedToQuarter
        lunchEnd = lunchEnd.roundedToQuarter

        let loaded = week
        week = Weekday.weekOrder.map { day in
            let existing = loaded.first { $0.day == day }
            return DaySchedule(
                day: day,
                enabled: existing?.enabled ?? !day.isWeekend,
                start: (existing?.start ?? TimeOfDay(8)).roundedToQuarter,
                end: (existing?.end ?? TimeOfDay(17)).roundedToQuarter)
        }

        daysOff = Array(Set(daysOff.filter { $0 >= today })).sorted()

        if let key = remoteKey, !AppSettings.isValidRemoteKey(key) {
            remoteKey = nil
        }
    }

    /// A remote key is 16 random bytes written as 32 lowercase hex characters.
    public static func isValidRemoteKey(_ key: String) -> Bool {
        key.count == 32 && key.allSatisfy { "0123456789abcdef".contains($0) }
    }
}

extension KeyedDecodingContainer {
    /// The value for `key`, or `fallback` when the key is missing, null or has the wrong type.
    /// Old or hand-edited settings files keep loading instead of resetting everything.
    func leniently<T: Decodable>(_ key: Key, default fallback: T) -> T {
        (try? decodeIfPresent(T.self, forKey: key)) ?? fallback
    }
}
