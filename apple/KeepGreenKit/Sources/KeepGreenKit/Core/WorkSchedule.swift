import Foundation

/// A stretch of time from `start` (inclusive) to `end` (exclusive).
public struct WorkWindow: Equatable, Sendable {
    public let start: Date
    public let end: Date

    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }

    public func contains(_ moment: Date) -> Bool { moment >= start && moment < end }
}

public struct ScheduleStatus: Equatable, Sendable {
    public let state: PresenceState
    public let nextChange: Date?

    public init(state: PresenceState, nextChange: Date?) {
        self.state = state
        self.nextChange = nextChange
    }
}

/// Pure schedule math: work windows, lunch breaks and days off. No clocks, no I/O.
/// Every function takes a Gregorian `calendar` whose time zone defines the wall clock (`Calendar.keepGreen` in the app).
public enum WorkSchedule {
    // Far enough to step over a long holiday when looking for the next work day.
    private static let lookaheadDays = 366

    public static func evaluate(_ settings: AppSettings, now: Date, calendar: Calendar = .keepGreen) -> ScheduleStatus {
        let today = LocalDate(now, calendar: calendar)
        if let window = currentWindow(settings, now: now, calendar: calendar) {
            let lunch = lunchFor(settings, day: today, calendar: calendar)
            if let lunch = lunch, lunch.contains(now) {
                return ScheduleStatus(state: .onBreak, nextChange: min(lunch.end, window.end))
            }

            var next = window.end
            if let lunch = lunch, lunch.start > now, lunch.start < next {
                next = lunch.start
            }
            return ScheduleStatus(state: .active, nextChange: next)
        }

        let state: PresenceState = settings.daysOff.contains(today) ? .dayOff : .offSchedule
        return ScheduleStatus(state: state, nextChange: nextStart(settings, now: now, calendar: calendar))
    }

    /// The work window running at `now`, if any.
    public static func currentWindow(_ settings: AppSettings, now: Date, calendar: Calendar = .keepGreen) -> WorkWindow? {
        // A window belongs to the day it starts on, so last night's shift can still be running.
        let today = LocalDate(now, calendar: calendar)
        for day in [today, today.adding(days: -1)] {
            if let window = windowFor(settings, day: day, calendar: calendar), window.contains(now) {
                return window
            }
        }
        return nil
    }

    /// The work window that starts on `day`, or nil when that day is off.
    public static func windowFor(_ settings: AppSettings, day: LocalDate, calendar: Calendar = .keepGreen) -> WorkWindow? {
        guard let schedule = settings.day(day.weekday), schedule.enabled, !settings.daysOff.contains(day) else {
            return nil
        }

        // Wall-clock times, so a night shift ends at its end time even across a daylight saving change.
        let start = day.date(at: schedule.start, calendar: calendar)
        let endDay = schedule.end > schedule.start ? day : day.adding(days: 1)
        var end = endDay.date(at: schedule.end, calendar: calendar)
        if end <= start {
            end = start.addingTimeInterval(schedule.length)
        }
        return WorkWindow(start: start, end: end)
    }

    public static func nextStart(_ settings: AppSettings, now: Date, calendar: Calendar = .keepGreen) -> Date? {
        guard settings.week.contains(where: { $0.enabled }) else { return nil }

        let today = LocalDate(now, calendar: calendar)
        for offset in 0...lookaheadDays {
            if let window = windowFor(settings, day: today.adding(days: offset), calendar: calendar), window.start > now {
                return window.start
            }
        }
        return nil
    }

    /// When "until the end of my workday" should stop: the current or today's window, else midnight.
    public static func endOfWorkday(_ settings: AppSettings, now: Date, calendar: Calendar = .keepGreen) -> Date {
        if let current = currentWindow(settings, now: now, calendar: calendar) {
            return current.end
        }

        let today = LocalDate(now, calendar: calendar)
        if let window = windowFor(settings, day: today, calendar: calendar), window.end > now {
            return window.end
        }
        return today.adding(days: 1).date(at: TimeOfDay(0), calendar: calendar)
    }

    private static func lunchFor(_ settings: AppSettings, day: LocalDate, calendar: Calendar) -> WorkWindow? {
        guard settings.lunchBreakEnabled, settings.lunchEnd > settings.lunchStart else { return nil }
        return WorkWindow(
            start: day.date(at: settings.lunchStart, calendar: calendar),
            end: day.date(at: settings.lunchEnd, calendar: calendar))
    }
}
