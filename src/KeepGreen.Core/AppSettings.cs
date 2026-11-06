using System.Collections.ObjectModel;
using System.Text.Json.Serialization;
using KeepGreen.Core.Remote;

namespace KeepGreen.Core;

/// <summary>How KeepGreen tells Windows that someone is at the keyboard.</summary>
public enum NudgeStyle
{
    /// <summary>A zero-distance mouse event. The cursor never moves.</summary>
    Invisible,

    /// <summary>Moves the cursor one pixel and straight back.</summary>
    MicroMove,

    /// <summary>Taps F15, a key that no physical keyboard has.</summary>
    PhantomKey,

    /// <summary>Sends no input at all; only keeps the PC and screen awake.</summary>
    AwakeOnly,
}

public enum ThemePreference
{
    System,
    Light,
    Dark,
}

/// <summary>Work hours for one day of the week. An end at or before the start runs past midnight.</summary>
public sealed class DaySchedule : ObservableObject
{
    private bool _enabled;
    private TimeOnly _start = new(8, 0);
    private TimeOnly _end = new(17, 0);

    public DayOfWeek Day { get; init; }

    public bool Enabled
    {
        get => _enabled;
        set => SetProperty(ref _enabled, value);
    }

    public TimeOnly Start
    {
        get => _start;
        set
        {
            if (SetProperty(ref _start, value))
                OnPropertyChanged(nameof(LengthText));
        }
    }

    public TimeOnly End
    {
        get => _end;
        set
        {
            if (SetProperty(ref _end, value))
                OnPropertyChanged(nameof(LengthText));
        }
    }

    [JsonIgnore]
    public string DayName => Day.ToString();

    /// <summary>Length of the work window. Equal start and end means a full 24 hours.</summary>
    [JsonIgnore]
    public TimeSpan Length
    {
        get
        {
            // TimeOnly subtraction wraps around midnight, so night shifts come out positive.
            var length = End - Start;
            return length == TimeSpan.Zero ? TimeSpan.FromDays(1) : length;
        }
    }

    [JsonIgnore]
    public string LengthText => Humanize.Duration(Length);
}

/// <summary>Everything the user can configure. Saved as JSON in %APPDATA%\KeepGreen.</summary>
public sealed class AppSettings : ObservableObject
{
    public const int MinIntervalSeconds = 15;

    // Teams switches to Away after 5 minutes idle; with ±20% variation this still nudges before 4m48s.
    public const int MaxIntervalSeconds = 240;

    public const int MinRemotePort = 1024;
    public const int MaxRemotePort = 65535;

    public static readonly DayOfWeek[] WeekOrder =
    [
        DayOfWeek.Monday, DayOfWeek.Tuesday, DayOfWeek.Wednesday, DayOfWeek.Thursday,
        DayOfWeek.Friday, DayOfWeek.Saturday, DayOfWeek.Sunday,
    ];

    private bool _isEnabled = true;
    private bool _useSchedule = true;
    private bool _lunchBreakEnabled;
    private TimeOnly _lunchStart = new(12, 0);
    private TimeOnly _lunchEnd = new(12, 30);
    private int _intervalSeconds = 60;
    private bool _randomizeInterval = true;
    private NudgeStyle _style = NudgeStyle.Invisible;
    private bool _pauseWhenLocked = true;
    private bool _pauseOnBattery;
    private bool _pauseOnLowBattery = true;
    private int _lowBatteryPercent = 15;
    private bool _onlyWhenAppsRunning;
    private string _watchedApps = "ms-teams, Teams, slack, Zoom";
    private bool _startWithWindows;
    private bool _startInTray = true;
    private bool _notifications = true;
    private ThemePreference _theme = ThemePreference.System;
    private bool _hotkeyEnabled = true;
    private bool _trayHintShown;
    private bool _remoteEnabled;
    private int _remotePort = RemoteServer.DefaultPort;
    private string _remoteKey = "";

    /// <summary>Raised after any setting changes, including days and days off.</summary>
    public event EventHandler? Changed;

    public bool IsEnabled { get => _isEnabled; set => SetProperty(ref _isEnabled, value); }

    public bool UseSchedule { get => _useSchedule; set => SetProperty(ref _useSchedule, value); }

    public ObservableCollection<DaySchedule> Week { get; set; } = CreateDefaultWeek();

    public ObservableCollection<DateOnly> DaysOff { get; set; } = [];

    public bool LunchBreakEnabled { get => _lunchBreakEnabled; set => SetProperty(ref _lunchBreakEnabled, value); }

    public TimeOnly LunchStart { get => _lunchStart; set => SetProperty(ref _lunchStart, value); }

    public TimeOnly LunchEnd { get => _lunchEnd; set => SetProperty(ref _lunchEnd, value); }

    public int IntervalSeconds { get => _intervalSeconds; set => SetProperty(ref _intervalSeconds, value); }

    public bool RandomizeInterval { get => _randomizeInterval; set => SetProperty(ref _randomizeInterval, value); }

    public NudgeStyle Style { get => _style; set => SetProperty(ref _style, value); }

    public bool PauseWhenLocked { get => _pauseWhenLocked; set => SetProperty(ref _pauseWhenLocked, value); }

    public bool PauseOnBattery { get => _pauseOnBattery; set => SetProperty(ref _pauseOnBattery, value); }

    public bool PauseOnLowBattery { get => _pauseOnLowBattery; set => SetProperty(ref _pauseOnLowBattery, value); }

    public int LowBatteryPercent { get => _lowBatteryPercent; set => SetProperty(ref _lowBatteryPercent, value); }

    public bool OnlyWhenAppsRunning { get => _onlyWhenAppsRunning; set => SetProperty(ref _onlyWhenAppsRunning, value); }

    /// <summary>Process names separated by commas, semicolons or spaces, e.g. "ms-teams, slack".</summary>
    public string WatchedApps { get => _watchedApps; set => SetProperty(ref _watchedApps, value); }

    public bool StartWithWindows { get => _startWithWindows; set => SetProperty(ref _startWithWindows, value); }

    public bool StartInTray { get => _startInTray; set => SetProperty(ref _startInTray, value); }

    public bool Notifications { get => _notifications; set => SetProperty(ref _notifications, value); }

    public ThemePreference Theme { get => _theme; set => SetProperty(ref _theme, value); }

    public bool HotkeyEnabled { get => _hotkeyEnabled; set => SetProperty(ref _hotkeyEnabled, value); }

    public bool TrayHintShown { get => _trayHintShown; set => SetProperty(ref _trayHintShown, value); }

    /// <summary>Lets the KeepGreen phone apps watch and control this PC over the local network.</summary>
    public bool RemoteEnabled { get => _remoteEnabled; set => SetProperty(ref _remoteEnabled, value); }

    public int RemotePort { get => _remotePort; set => SetProperty(ref _remotePort, value); }

    /// <summary>The key shared with paired phones: 32 lowercase hex characters, or empty until the remote is first turned on.</summary>
    public string RemoteKey { get => _remoteKey; set => SetProperty(ref _remoteKey, value); }

    public DaySchedule? GetDay(DayOfWeek day) => Week.FirstOrDefault(d => d.Day == day);

    /// <summary>The watched process names, without ".exe" and without duplicates.</summary>
    public IReadOnlyList<string> WatchedAppNames() =>
        WatchedApps
            .Split([',', ';', ' '], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Select(name => name.EndsWith(".exe", StringComparison.OrdinalIgnoreCase) ? name[..^4] : name)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray();

    public static ObservableCollection<DaySchedule> CreateDefaultWeek() =>
        new(WeekOrder.Select(day => new DaySchedule
        {
            Day = day,
            Enabled = day is not (DayOfWeek.Saturday or DayOfWeek.Sunday),
            Start = new TimeOnly(8, 0),
            End = new TimeOnly(17, 0),
        }));

    /// <summary>Repairs a loaded file: clamps numbers, restores missing days, drops past days off.</summary>
    public void Normalize(DateOnly today)
    {
        IntervalSeconds = Math.Clamp(IntervalSeconds, MinIntervalSeconds, MaxIntervalSeconds);
        LowBatteryPercent = Math.Clamp(LowBatteryPercent, 5, 95);
        LunchStart = RoundToQuarter(LunchStart);
        LunchEnd = RoundToQuarter(LunchEnd);
        WatchedApps ??= "";
        RemotePort = Math.Clamp(RemotePort, MinRemotePort, MaxRemotePort);
        if (!RemoteSignature.IsValidKey(RemoteKey))
            RemoteKey = "";

        var loaded = Week ?? [];
        Week = new ObservableCollection<DaySchedule>(WeekOrder.Select(day =>
        {
            var existing = loaded.FirstOrDefault(d => d.Day == day);
            return new DaySchedule
            {
                Day = day,
                Enabled = existing?.Enabled ?? day is not (DayOfWeek.Saturday or DayOfWeek.Sunday),
                Start = RoundToQuarter(existing?.Start ?? new TimeOnly(8, 0)),
                End = RoundToQuarter(existing?.End ?? new TimeOnly(17, 0)),
            };
        }));

        DaysOff = new ObservableCollection<DateOnly>((DaysOff ?? []).Where(d => d >= today).Distinct().Order());
    }

    /// <summary>Starts raising <see cref="Changed"/> for nested changes too. Call once, after loading.</summary>
    public void TrackChanges()
    {
        PropertyChanged += (_, _) => Changed?.Invoke(this, EventArgs.Empty);
        foreach (var day in Week)
            day.PropertyChanged += (_, _) => Changed?.Invoke(this, EventArgs.Empty);
        DaysOff.CollectionChanged += (_, _) => Changed?.Invoke(this, EventArgs.Empty);
    }

    public static TimeOnly RoundToQuarter(TimeOnly time) => new(time.Hour, time.Minute / 15 * 15);
}
