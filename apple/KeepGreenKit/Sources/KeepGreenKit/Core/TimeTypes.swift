import Foundation

public extension Calendar {
    /// Gregorian, in the device's current time zone. All schedule math uses this,
    /// whatever calendar the user prefers for display, so years, months and weekdays always line up.
    static var keepGreen: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        return calendar
    }
}

/// A day of the week. The raw values match the names the Windows app writes, so the JSON reads the same.
public enum Weekday: String, Codable, CaseIterable, Identifiable, Sendable {
    case monday = "Monday"
    case tuesday = "Tuesday"
    case wednesday = "Wednesday"
    case thursday = "Thursday"
    case friday = "Friday"
    case saturday = "Saturday"
    case sunday = "Sunday"

    /// Monday first, the way work weeks are usually written.
    public static let weekOrder: [Weekday] = [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]

    public var id: String { rawValue }

    public var name: String { rawValue }

    public var shortName: String { String(rawValue.prefix(3)) }

    public var isWeekend: Bool { self == .saturday || self == .sunday }
}

/// A wall-clock time without a date, like "08:30". Stored in JSON as "HH:mm".
public struct TimeOfDay: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let hour: Int
    public let minute: Int

    public init(_ hour: Int, _ minute: Int = 0) {
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
    }

    /// Wraps around midnight, so 1500 minutes is 01:00.
    public init(minutesSinceMidnight: Int) {
        let wrapped = ((minutesSinceMidnight % 1440) + 1440) % 1440
        self.init(wrapped / 60, wrapped % 60)
    }

    /// Accepts "8:30", "08:30" and "08:30:00" (the format .NET uses for TimeOnly).
    public init?(string: String) {
        let parts = string.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard parts.count == 2 || parts.count == 3,
              let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...23).contains(hour), (0...59).contains(minute)
        else { return nil }
        self.init(hour, minute)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let time = TimeOfDay(string: text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected a time like 08:30, got \(text)")
        }
        self = time
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }

    /// Every quarter hour of the day, for the time pickers.
    public static let quarterHours: [TimeOfDay] = (0..<96).map { TimeOfDay(minutesSinceMidnight: $0 * 15) }

    public var minutesSinceMidnight: Int { hour * 60 + minute }

    public var roundedToQuarter: TimeOfDay { TimeOfDay(hour, minute / 15 * 15) }

    /// 24-hour "HH:mm", matching the time pickers.
    public var description: String { Humanize.twoDigits(hour) + ":" + Humanize.twoDigits(minute) }

    public static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool {
        lhs.minutesSinceMidnight < rhs.minutesSinceMidnight
    }
}

/// A calendar date without a time, like 24 December 2026. Stored in JSON as "yyyy-MM-dd".
/// Arithmetic uses Julian day numbers, so it never trips over daylight saving time.
public struct LocalDate: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    /// Out-of-range days roll over, so 30 February becomes 1 or 2 March.
    public init(year: Int, month: Int, day: Int) {
        let julian = LocalDate.julianDayNumber(year: year, month: min(max(month, 1), 12), day: min(max(day, 1), 31))
        self.init(julianDay: julian)
    }

    /// The date `date` falls on in `calendar`'s time zone. `calendar` must be Gregorian, like `Calendar.keepGreen`.
    public init(_ date: Date, calendar: Calendar = .keepGreen) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    public init(julianDay: Int) {
        // Fliegel and Van Flandern's conversion from a Julian day number to a Gregorian date.
        let a = julianDay + 32044
        let b = (4 * a + 3) / 146_097
        let c = a - 146_097 * b / 4
        let d = (4 * c + 3) / 1461
        let e = c - 1461 * d / 4
        let m = (5 * e + 2) / 153
        day = e - (153 * m + 2) / 5 + 1
        month = m + 3 - 12 * (m / 10)
        year = 100 * b + d - 4800 + m / 10
    }

    public init?(string: String) {
        let parts = string.trimmingCharacters(in: .whitespaces).split(separator: "-")
        guard parts.count == 3, let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...12).contains(month), (1...31).contains(day)
        else { return nil }
        self.init(year: year, month: month, day: day)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let date = LocalDate(string: text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected a date like 2026-12-24, got \(text)")
        }
        self = date
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }

    public var julianDay: Int { LocalDate.julianDayNumber(year: year, month: month, day: day) }

    public var weekday: Weekday {
        // Julian day 0 was a Monday.
        Weekday.weekOrder[((julianDay % 7) + 7) % 7]
    }

    public func adding(days: Int) -> LocalDate { LocalDate(julianDay: julianDay + days) }

    /// Whole days from `other` to this date; negative when this date is earlier.
    public func days(since other: LocalDate) -> Int { julianDay - other.julianDay }

    /// The moment this date reaches `time` on the wall clock of `calendar`'s time zone.
    public func date(at time: TimeOfDay = TimeOfDay(0), calendar: Calendar = .keepGreen) -> Date {
        let parts = DateComponents(year: year, month: month, day: day, hour: time.hour, minute: time.minute)
        return calendar.date(from: parts) ?? Date(timeIntervalSince1970: 0)
    }

    /// "yyyy-MM-dd".
    public var description: String {
        let paddedYear = String(repeating: "0", count: max(0, 4 - String(year).count)) + String(year)
        return paddedYear + "-" + Humanize.twoDigits(month) + "-" + Humanize.twoDigits(day)
    }

    public static func < (lhs: LocalDate, rhs: LocalDate) -> Bool { lhs.julianDay < rhs.julianDay }

    private static func julianDayNumber(year: Int, month: Int, day: Int) -> Int {
        let a = (14 - month) / 12
        let y = year + 4800 - a
        let m = month + 12 * a - 3
        return day + (153 * m + 2) / 5 + 365 * y + y / 4 - y / 100 + y / 400 - 32045
    }
}
