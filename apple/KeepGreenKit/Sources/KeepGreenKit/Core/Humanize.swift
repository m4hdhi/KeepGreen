import Foundation

/// Short, friendly text for times and durations. English and 24-hour on purpose, so every
/// KeepGreen app (and the phone remote, which shows these sentences as-is) reads the same.
public enum Humanize {
    private static let monthAbbreviations = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    /// 24-hour clock time, matching the time pickers: "08:30".
    public static func time(_ moment: Date, calendar: Calendar = .keepGreen) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: moment)
        return TimeOfDay(parts.hour ?? 0, parts.minute ?? 0).description
    }

    /// "today at 17:00", "tomorrow at 08:00", "Monday at 08:00" or "on 24 Dec at 08:00".
    public static func when(_ target: Date, now: Date, calendar: Calendar = .keepGreen) -> String {
        let clock = time(target, calendar: calendar)
        let day = LocalDate(target, calendar: calendar)
        switch day.days(since: LocalDate(now, calendar: calendar)) {
        case 0:
            return "today at \(clock)"
        case 1:
            return "tomorrow at \(clock)"
        case 2..<7:
            return "\(day.weekday.name) at \(clock)"
        default:
            return "on \(day.day) \(monthAbbreviations[day.month - 1]) at \(clock)"
        }
    }

    /// "42 s", "5 min", "6 h 12 min" or "2 h".
    public static func duration(_ seconds: TimeInterval) -> String {
        let total = seconds.isFinite ? min(max(seconds, 0), 1e12) : 0
        if total < 60 {
            return "\(Int(total)) s"
        }
        if total < 3600 {
            return "\(Int(total / 60)) min"
        }

        let whole = Int(total)
        let hours = whole / 3600
        let minutes = (whole % 3600) / 60
        return minutes == 0 ? "\(hours) h" : "\(hours) h \(minutes) min"
    }

    static func twoDigits(_ value: Int) -> String {
        (0..<10).contains(value) ? "0\(value)" : "\(value)"
    }
}
