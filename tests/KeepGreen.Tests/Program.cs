using KeepGreen.Core;

// 2 November 2026 is a Monday; 6 November is a Friday.
static DateTime On(int day, int hour, int minute = 0) => new(2026, 11, day, hour, minute, 0);

static AppSettings Defaults()
{
    var settings = new AppSettings();
    settings.Normalize(new DateOnly(2026, 11, 1));
    return settings;
}

static PresenceContext At(DateTime now, bool locked = false, bool onBattery = false, int battery = 100, bool appRunning = true) =>
    new(now, locked, onBattery, battery, appRunning);

var tests = new (string Name, Action Run)[]
{
    ("Weekday inside work hours is active until the end", () =>
    {
        var status = WorkSchedule.Evaluate(Defaults(), On(2, 10));
        Assert.Equal(PresenceState.Active, status.State);
        Assert.Equal<DateTime?>(On(2, 17), status.NextChange);
    }),
    ("Before work hours waits for today's start", () =>
    {
        var status = WorkSchedule.Evaluate(Defaults(), On(2, 7));
        Assert.Equal(PresenceState.OffSchedule, status.State);
        Assert.Equal<DateTime?>(On(2, 8), status.NextChange);
    }),
    ("Friday evening skips the weekend", () =>
    {
        var status = WorkSchedule.Evaluate(Defaults(), On(6, 18));
        Assert.Equal(PresenceState.OffSchedule, status.State);
        Assert.Equal<DateTime?>(On(9, 8), status.NextChange);
    }),
    ("Saturday is off by default", () =>
    {
        var status = WorkSchedule.Evaluate(Defaults(), On(7, 12));
        Assert.Equal(PresenceState.OffSchedule, status.State);
        Assert.Equal<DateTime?>(On(9, 8), status.NextChange);
    }),
    ("Lunch break pauses and resumes", () =>
    {
        var settings = Defaults();
        settings.LunchBreakEnabled = true;
        var during = WorkSchedule.Evaluate(settings, On(2, 12, 10));
        Assert.Equal(PresenceState.Break, during.State);
        Assert.Equal<DateTime?>(On(2, 12, 30), during.NextChange);
        var before = WorkSchedule.Evaluate(settings, On(2, 11));
        Assert.Equal(PresenceState.Active, before.State);
        Assert.Equal<DateTime?>(On(2, 12), before.NextChange);
    }),
    ("A day off is skipped", () =>
    {
        var settings = Defaults();
        settings.DaysOff.Add(new DateOnly(2026, 11, 2));
        var status = WorkSchedule.Evaluate(settings, On(2, 10));
        Assert.Equal(PresenceState.DayOff, status.State);
        Assert.Equal<DateTime?>(On(3, 8), status.NextChange);
    }),
    ("Night shift runs past midnight", () =>
    {
        var settings = Defaults();
        foreach (var day in settings.Week)
            day.Enabled = day.Day == DayOfWeek.Monday;
        var monday = settings.GetDay(DayOfWeek.Monday)!;
        monday.Start = new TimeOnly(22, 0);
        monday.End = new TimeOnly(6, 0);

        var night = WorkSchedule.Evaluate(settings, On(3, 3));
        Assert.Equal(PresenceState.Active, night.State);
        Assert.Equal<DateTime?>(On(3, 6), night.NextChange);
        var morning = WorkSchedule.Evaluate(settings, On(3, 7));
        Assert.Equal(PresenceState.OffSchedule, morning.State);
        Assert.Equal<DateTime?>(On(9, 22), morning.NextChange);
    }),
    ("Equal start and end means a full day", () =>
    {
        var settings = Defaults();
        var monday = settings.GetDay(DayOfWeek.Monday)!;
        monday.Start = new TimeOnly(0, 0);
        monday.End = new TimeOnly(0, 0);
        var status = WorkSchedule.Evaluate(settings, On(2, 23, 30));
        Assert.Equal(PresenceState.Active, status.State);
        Assert.Equal<DateTime?>(On(3, 0), status.NextChange);
    }),
    ("Master switch off means disabled", () =>
    {
        var settings = Defaults();
        settings.IsEnabled = false;
        Assert.Equal(PresenceState.Disabled, PresencePolicy.Evaluate(settings, At(On(2, 10)), null).State);
    }),
    ("A boost beats the switch and the schedule", () =>
    {
        var settings = Defaults();
        settings.IsEnabled = false;
        var decision = PresencePolicy.Evaluate(settings, At(On(7, 12)), On(7, 13));
        Assert.Equal(PresenceState.Active, decision.State);
        Assert.True(decision.IsBoosted, "expected a boosted decision");
        Assert.Equal<DateTime?>(On(7, 13), decision.NextChange);
    }),
    ("An expired boost no longer counts", () =>
    {
        var decision = PresencePolicy.Evaluate(Defaults(), At(On(7, 12)), On(7, 11));
        Assert.Equal(PresenceState.OffSchedule, decision.State);
        Assert.True(!decision.IsBoosted, "expected no boost");
    }),
    ("Locking the PC pauses, even when boosted", () =>
    {
        var decision = PresencePolicy.Evaluate(Defaults(), At(On(2, 10), locked: true), On(2, 11));
        Assert.Equal(PresenceState.Locked, decision.State);
    }),
    ("Low battery pauses only when unplugged", () =>
    {
        Assert.Equal(PresenceState.LowBattery, PresencePolicy.Evaluate(Defaults(), At(On(2, 10), onBattery: true, battery: 10), null).State);
        Assert.Equal(PresenceState.Active, PresencePolicy.Evaluate(Defaults(), At(On(2, 10), onBattery: false, battery: 10), null).State);
        Assert.Equal(PresenceState.Active, PresencePolicy.Evaluate(Defaults(), At(On(2, 10), onBattery: true, battery: -1), null).State);
    }),
    ("Pause on battery power", () =>
    {
        var settings = Defaults();
        settings.PauseOnBattery = true;
        Assert.Equal(PresenceState.OnBattery, PresencePolicy.Evaluate(settings, At(On(2, 10), onBattery: true, battery: 80), null).State);
    }),
    ("Waits for watched apps", () =>
    {
        var settings = Defaults();
        settings.OnlyWhenAppsRunning = true;
        Assert.Equal(PresenceState.WaitingForApp, PresencePolicy.Evaluate(settings, At(On(2, 10), appRunning: false), null).State);
        Assert.Equal(PresenceState.Active, PresencePolicy.Evaluate(settings, At(On(2, 10), appRunning: true), null).State);
    }),
    ("Schedule off runs around the clock", () =>
    {
        var settings = Defaults();
        settings.UseSchedule = false;
        var decision = PresencePolicy.Evaluate(settings, At(On(7, 3)), null);
        Assert.Equal(PresenceState.Active, decision.State);
        Assert.Equal<DateTime?>(null, decision.NextChange);
    }),
    ("End of workday", () =>
    {
        Assert.Equal(On(2, 17), WorkSchedule.EndOfWorkday(Defaults(), On(2, 10)));
        Assert.Equal(On(2, 17), WorkSchedule.EndOfWorkday(Defaults(), On(2, 7)));
        Assert.Equal(On(8, 0), WorkSchedule.EndOfWorkday(Defaults(), On(7, 12)));
    }),
    ("Settings survive a save and load", () =>
    {
        var folder = Path.Combine(Path.GetTempPath(), "KeepGreen.Tests", Guid.NewGuid().ToString("N"));
        try
        {
            var store = new SettingsStore(folder);
            var settings = Defaults();
            settings.Style = NudgeStyle.PhantomKey;
            settings.IntervalSeconds = 90;
            settings.LunchStart = new TimeOnly(13, 15);
            settings.DaysOff.Add(new DateOnly(2026, 12, 24));
            settings.GetDay(DayOfWeek.Saturday)!.Enabled = true;
            store.SaveSettings(settings);

            var loaded = store.LoadSettings(new DateOnly(2026, 11, 1));
            Assert.Equal(NudgeStyle.PhantomKey, loaded.Style);
            Assert.Equal(90, loaded.IntervalSeconds);
            Assert.Equal(new TimeOnly(13, 15), loaded.LunchStart);
            Assert.Equal(new DateOnly(2026, 12, 24), loaded.DaysOff.Single());
            Assert.True(loaded.GetDay(DayOfWeek.Saturday)!.Enabled, "Saturday should stay enabled");
        }
        finally
        {
            if (Directory.Exists(folder))
                Directory.Delete(folder, recursive: true);
        }
    }),
    ("A corrupt settings file falls back to defaults", () =>
    {
        var folder = Path.Combine(Path.GetTempPath(), "KeepGreen.Tests", Guid.NewGuid().ToString("N"));
        try
        {
            Directory.CreateDirectory(folder);
            var store = new SettingsStore(folder);
            File.WriteAllText(store.SettingsPath, "{ not json");
            var loaded = store.LoadSettings(new DateOnly(2026, 11, 1));
            Assert.Equal(60, loaded.IntervalSeconds);
            Assert.True(File.Exists(store.SettingsPath + ".broken"), "the broken file should be kept");
        }
        finally
        {
            if (Directory.Exists(folder))
                Directory.Delete(folder, recursive: true);
        }
    }),
    ("Normalize repairs bad values", () =>
    {
        var settings = new AppSettings { IntervalSeconds = 5, LowBatteryPercent = 200 };
        settings.Week.RemoveAt(3);
        settings.GetDay(DayOfWeek.Monday)!.Start = new TimeOnly(8, 10);
        settings.DaysOff.Add(new DateOnly(2026, 10, 1));
        settings.Normalize(new DateOnly(2026, 11, 1));
        Assert.Equal(AppSettings.MinIntervalSeconds, settings.IntervalSeconds);
        Assert.Equal(95, settings.LowBatteryPercent);
        Assert.Equal(7, settings.Week.Count);
        Assert.Equal(new TimeOnly(8, 0), settings.GetDay(DayOfWeek.Monday)!.Start);
        Assert.Equal(0, settings.DaysOff.Count);

        settings.IntervalSeconds = 999;
        settings.Normalize(new DateOnly(2026, 11, 1));
        Assert.Equal(AppSettings.MaxIntervalSeconds, settings.IntervalSeconds);
    }),
    ("Watched app names are cleaned up", () =>
    {
        var settings = new AppSettings { WatchedApps = "ms-teams.exe, Slack;  zoom slack" };
        Assert.Equal("ms-teams|Slack|zoom", string.Join("|", settings.WatchedAppNames()));
    }),
    ("Friendly times", () =>
    {
        var now = On(2, 9);
        Assert.True(Humanize.When(On(2, 17), now).StartsWith("today at", StringComparison.Ordinal), "today");
        Assert.True(Humanize.When(On(3, 8), now).StartsWith("tomorrow at", StringComparison.Ordinal), "tomorrow");
        Assert.True(Humanize.When(On(5, 8), now).StartsWith("Thursday at", StringComparison.Ordinal), "weekday");
        Assert.True(Humanize.When(On(20, 8), now).StartsWith("on 20 Nov at", StringComparison.Ordinal), "date");
    }),
    ("Friendly durations", () =>
    {
        Assert.Equal("42 s", Humanize.Duration(TimeSpan.FromSeconds(42)));
        Assert.Equal("5 min", Humanize.Duration(TimeSpan.FromMinutes(5.5)));
        Assert.Equal("6 h 12 min", Humanize.Duration(new TimeSpan(6, 12, 30)));
        Assert.Equal("2 h", Humanize.Duration(TimeSpan.FromHours(2)));
    }),
};

var failed = 0;
foreach (var (name, run) in tests)
{
    try
    {
        run();
        Console.WriteLine($"  PASS  {name}");
    }
    catch (Exception ex)
    {
        failed++;
        Console.WriteLine($"  FAIL  {name}: {ex.Message}");
    }
}

Console.WriteLine();
Console.WriteLine($"{tests.Length - failed}/{tests.Length} tests passed");
return failed == 0 ? 0 : 1;

internal static class Assert
{
    public static void Equal<T>(T expected, T actual)
    {
        if (!EqualityComparer<T>.Default.Equals(expected, actual))
            throw new InvalidOperationException($"expected <{expected}> but got <{actual}>");
    }

    public static void True(bool condition, string message)
    {
        if (!condition)
            throw new InvalidOperationException(message);
    }
}
