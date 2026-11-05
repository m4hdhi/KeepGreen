using System.Globalization;

namespace KeepGreen.Core;

/// <summary>Short, friendly text for times and durations.</summary>
public static class Humanize
{
    /// <summary>24-hour clock time, matching the time pickers.</summary>
    public static string Time(DateTime moment) => moment.ToString("HH:mm", CultureInfo.InvariantCulture);

    /// <summary>"today at 17:00", "tomorrow at 08:00", "Monday at 08:00" or "on 24 Dec at 08:00".</summary>
    public static string When(DateTime target, DateTime now)
    {
        var time = Time(target);
        var days = (target.Date - now.Date).Days;
        return days switch
        {
            0 => $"today at {time}",
            1 => $"tomorrow at {time}",
            > 1 and < 7 => $"{target.ToString("dddd", CultureInfo.InvariantCulture)} at {time}",
            _ => $"on {target.ToString("d MMM", CultureInfo.InvariantCulture)} at {time}",
        };
    }

    /// <summary>"42 s", "5 min" or "6 h 12 min".</summary>
    public static string Duration(TimeSpan span)
    {
        if (span < TimeSpan.Zero)
            span = TimeSpan.Zero;
        if (span.TotalSeconds < 60)
            return $"{(int)span.TotalSeconds} s";
        if (span.TotalMinutes < 60)
            return $"{(int)span.TotalMinutes} min";

        var hours = (int)span.TotalHours;
        return span.Minutes == 0 ? $"{hours} h" : $"{hours} h {span.Minutes} min";
    }
}
