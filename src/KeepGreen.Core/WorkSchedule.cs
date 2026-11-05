namespace KeepGreen.Core;

public readonly record struct WorkWindow(DateTime Start, DateTime End)
{
    public bool Contains(DateTime moment) => moment >= Start && moment < End;
}

public readonly record struct ScheduleStatus(PresenceState State, DateTime? NextChange);

/// <summary>Pure schedule math: work windows, lunch breaks and days off. No clocks, no I/O.</summary>
public static class WorkSchedule
{
    // Far enough to step over a long holiday when looking for the next work day.
    private const int LookaheadDays = 366;

    public static ScheduleStatus Evaluate(AppSettings settings, DateTime now)
    {
        if (CurrentWindow(settings, now) is { } window)
        {
            var lunch = LunchFor(settings, now.Date);
            if (lunch is { } current && current.Contains(now))
                return new ScheduleStatus(PresenceState.Break, Earliest(current.End, window.End));

            var next = window.End;
            if (lunch is { } upcoming && upcoming.Start > now && upcoming.Start < next)
                next = upcoming.Start;
            return new ScheduleStatus(PresenceState.Active, next);
        }

        var state = settings.DaysOff.Contains(DateOnly.FromDateTime(now)) ? PresenceState.DayOff : PresenceState.OffSchedule;
        return new ScheduleStatus(state, NextStart(settings, now));
    }

    /// <summary>The work window running at <paramref name="now"/>, if any.</summary>
    public static WorkWindow? CurrentWindow(AppSettings settings, DateTime now)
    {
        // A window belongs to the day it starts on, so last night's shift can still be running.
        foreach (var day in new[] { now.Date, now.Date.AddDays(-1) })
        {
            if (WindowFor(settings, day) is { } window && window.Contains(now))
                return window;
        }

        return null;
    }

    /// <summary>The work window that starts on <paramref name="day"/>, or null on a day off.</summary>
    public static WorkWindow? WindowFor(AppSettings settings, DateTime day)
    {
        var schedule = settings.GetDay(day.DayOfWeek);
        if (schedule is not { Enabled: true } || settings.DaysOff.Contains(DateOnly.FromDateTime(day)))
            return null;

        var start = day.Date + schedule.Start.ToTimeSpan();
        return new WorkWindow(start, start + schedule.Length);
    }

    public static DateTime? NextStart(AppSettings settings, DateTime now)
    {
        for (var offset = 0; offset <= LookaheadDays; offset++)
        {
            if (WindowFor(settings, now.Date.AddDays(offset)) is { } window && window.Start > now)
                return window.Start;
        }

        return null;
    }

    /// <summary>When "until end of workday" should stop: the current or today's window, else midnight.</summary>
    public static DateTime EndOfWorkday(AppSettings settings, DateTime now)
    {
        if (CurrentWindow(settings, now) is { } current)
            return current.End;
        if (WindowFor(settings, now.Date) is { } today && today.End > now)
            return today.End;
        return now.Date.AddDays(1);
    }

    private static WorkWindow? LunchFor(AppSettings settings, DateTime day)
    {
        if (!settings.LunchBreakEnabled || settings.LunchEnd <= settings.LunchStart)
            return null;
        return new WorkWindow(day + settings.LunchStart.ToTimeSpan(), day + settings.LunchEnd.ToTimeSpan());
    }

    private static DateTime Earliest(DateTime a, DateTime b) => a < b ? a : b;
}
