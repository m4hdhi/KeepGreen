using System.ComponentModel;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Windows.Threading;
using KeepGreen.Core;
using KeepGreen.Native;
using Microsoft.Win32;
using Forms = System.Windows.Forms;

namespace KeepGreen.Services;

internal readonly record struct PresenceTransition(PresenceDecision Previous, PresenceDecision Current);

/// <summary>
/// The heart of KeepGreen. Once a second it asks <see cref="PresencePolicy"/> whether to be working,
/// holds the PC awake while it is, and nudges only after the user has been idle long enough.
/// </summary>
internal sealed class PresenceEngine : ObservableObject, IDisposable
{
    private static readonly TimeSpan AppScanInterval = TimeSpan.FromSeconds(5);
    private static readonly TimeSpan StatsSaveInterval = TimeSpan.FromMinutes(1);

    private const string BlockedWarning =
        "Windows is ignoring KeepGreen's nudges. This usually means an app running as administrator is in front. " +
        "Switch to another window, or run KeepGreen as administrator.";

    private readonly AppSettings _settings;
    private readonly SettingsStore _store;
    private readonly DispatcherTimer _timer;
    private DailyStats _stats;
    private PresenceDecision _decision = new(PresenceState.Disabled, false, null);
    private DateTime? _boostUntil;
    private DateTime _lastTick = DateTime.Now;
    private DateTime _lastStatsSave = DateTime.Now;
    private DateTime _lastAppScan = DateTime.MinValue;
    private DateTime _nextAttemptAllowed = DateTime.MinValue;
    private DateTime? _awaitingVerification;
    private bool _watchedAppRunning;
    private volatile bool _isLocked;
    private bool _holdingAwake;
    private double _thresholdSeconds;
    private int _failedNudges;
    private TimeSpan _idle;
    private string? _warning;

    public PresenceEngine(AppSettings settings, SettingsStore store)
    {
        _settings = settings;
        _store = store;
        _stats = store.LoadStats(DateOnly.FromDateTime(DateTime.Now));
        _thresholdSeconds = NextThreshold();

        _timer = new DispatcherTimer(DispatcherPriority.Normal) { Interval = TimeSpan.FromSeconds(1) };
        _timer.Tick += (_, _) => Tick();

        _settings.PropertyChanged += OnSettingsChanged;
        SystemEvents.SessionSwitch += OnSessionSwitch;
        SystemEvents.PowerModeChanged += OnPowerModeChanged;
    }

    public event EventHandler<PresenceTransition>? StateChanged;

    public PresenceState State => _decision.State;

    public bool IsActive => _decision.IsActive;

    public bool HasBoost => _boostUntil is not null;

    public string Headline { get; private set; } = "Starting…";

    public string Detail { get; private set; } = "";

    public string ScheduleSummary { get; private set; } = "";

    public string ShortStatus => _decision.State switch
    {
        PresenceState.Active => _decision.IsBoosted ? "Boosted" : "Active",
        PresenceState.Disabled => "Off",
        PresenceState.OffSchedule => "Off schedule",
        PresenceState.DayOff => "Day off",
        PresenceState.Break => "On a break",
        PresenceState.Locked => "Paused: locked",
        PresenceState.OnBattery or PresenceState.LowBattery => "Paused: battery",
        PresenceState.WaitingForApp => "Waiting for apps",
        _ => "",
    };

    public string IdleText => Humanize.Duration(_idle);

    public string NextNudgeText =>
        !IsActive ? "—"
        : _settings.Style == NudgeStyle.AwakeOnly ? "Off"
        : Humanize.Duration(TimeSpan.FromSeconds(Math.Max(0, _thresholdSeconds - _idle.TotalSeconds)));

    public string NudgesTodayText => _stats.Nudges.ToString("N0", CultureInfo.CurrentCulture);

    public string LastNudgeText => _stats.LastNudge is { } last ? $"Last one at {Humanize.Time(last)}" : "None yet today";

    public string GreenTimeText => Humanize.Duration(TimeSpan.FromSeconds(_stats.ActiveSeconds));

    public string BoostText => _boostUntil is { } until ? $"Boost on until {Humanize.Time(until)}" : "";

    public string? Warning
    {
        get => _warning;
        private set
        {
            if (SetProperty(ref _warning, value))
                OnPropertyChanged(nameof(HasWarning));
        }
    }

    public bool HasWarning => _warning is not null;

    public void Start()
    {
        Tick();
        _timer.Start();
    }

    public void Boost(TimeSpan duration) => SetBoost(DateTime.Now + duration);

    public void BoostUntilEndOfWorkday() => SetBoost(WorkSchedule.EndOfWorkday(_settings, DateTime.Now));

    public void CancelBoost() => SetBoost(null);

    /// <summary>Sends one nudge right away and checks that Windows registered it.</summary>
    public async Task<(bool Ok, string Message)> RunSelfTestAsync()
    {
        var style = _settings.Style == NudgeStyle.AwakeOnly ? NudgeStyle.Invisible : _settings.Style;
        if (!InputNudger.Send(style))
            return (false, "Windows refused the input. If an app running as administrator is in front, switch to another window and try again.");

        await Task.Delay(400);
        var idle = NativeMethods.GetIdleTime();
        return idle < TimeSpan.FromSeconds(1)
            ? (true, "Activity registered: the Windows idle timer went back to 0. Teams, Slack and Zoom will see you as active.")
            : (false, $"Windows didn't register the nudge (idle time is still {Humanize.Duration(idle)}). An app running as administrator may be in front.");
    }

    public void Dispose()
    {
        _timer.Stop();
        _settings.PropertyChanged -= OnSettingsChanged;
        SystemEvents.SessionSwitch -= OnSessionSwitch;
        SystemEvents.PowerModeChanged -= OnPowerModeChanged;
        UpdateAwakeRequest(active: false);
        SaveStats();
    }

    private void Tick()
    {
        var now = DateTime.Now;
        RollOverDay(now);

        if (_boostUntil is { } until && until <= now)
            _boostUntil = null;

        var power = Forms.SystemInformation.PowerStatus;
        var onBattery = power.PowerLineStatus == Forms.PowerLineStatus.Offline;
        var battery = power.BatteryLifePercent is >= 0 and <= 1 ? (int)Math.Round(power.BatteryLifePercent * 100) : -1;
        var context = new PresenceContext(now, _isLocked, onBattery, battery, IsWatchedAppRunning(now));
        var decision = PresencePolicy.Evaluate(_settings, context, _boostUntil);

        UpdateAwakeRequest(decision.IsActive);
        _idle = NativeMethods.GetIdleTime();

        if (decision.IsActive)
        {
            var elapsed = now - _lastTick;
            if (elapsed > TimeSpan.Zero && elapsed < TimeSpan.FromSeconds(5))
                _stats.ActiveSeconds += elapsed.TotalSeconds;

            VerifyLastNudge(now);
            var due = _idle.TotalSeconds >= _thresholdSeconds && now >= _nextAttemptAllowed;
            if (_settings.Style != NudgeStyle.AwakeOnly && due)
                SendNudge(now);
        }
        else
        {
            _awaitingVerification = null;
        }

        _lastTick = now;
        var previous = _decision;
        _decision = decision;
        UpdateTexts(now);

        if (previous.State != decision.State || previous.IsBoosted != decision.IsBoosted)
            StateChanged?.Invoke(this, new PresenceTransition(previous, decision));

        if (now - _lastStatsSave >= StatsSaveInterval)
            SaveStats();
    }

    private void SendNudge(DateTime now)
    {
        var sent = InputNudger.Send(_settings.Style);
        _nextAttemptAllowed = now + TimeSpan.FromSeconds(sent ? 2 : 15);
        _thresholdSeconds = NextThreshold();
        if (!sent)
        {
            Warning = BlockedWarning;
            return;
        }

        _awaitingVerification = now;
        _stats.Nudges++;
        _stats.LastNudge = now;
    }

    /// <summary>A second after a nudge, checks that the idle timer actually reset.</summary>
    private void VerifyLastNudge(DateTime now)
    {
        if (_awaitingVerification is not { } sentAt || now - sentAt < TimeSpan.FromSeconds(1))
            return;

        _awaitingVerification = null;
        if (_idle <= now - sentAt + TimeSpan.FromSeconds(1))
        {
            _failedNudges = 0;
            Warning = null;
            return;
        }

        _nextAttemptAllowed = now + TimeSpan.FromSeconds(15);
        if (++_failedNudges >= 2)
            Warning = BlockedWarning;
    }

    private void UpdateAwakeRequest(bool active)
    {
        if (active)
        {
            // Re-asserted every tick: cheap, and survives Modern Standby silently dropping the request.
            NativeMethods.SetThreadExecutionState(
                NativeMethods.ExecutionState.Continuous |
                NativeMethods.ExecutionState.SystemRequired |
                NativeMethods.ExecutionState.DisplayRequired);
            _holdingAwake = true;
        }
        else if (_holdingAwake)
        {
            NativeMethods.SetThreadExecutionState(NativeMethods.ExecutionState.Continuous);
            _holdingAwake = false;
        }
    }

    private bool IsWatchedAppRunning(DateTime now)
    {
        if (!_settings.OnlyWhenAppsRunning)
            return true;
        if (now - _lastAppScan < AppScanInterval)
            return _watchedAppRunning;

        _lastAppScan = now;
        _watchedAppRunning = _settings.WatchedAppNames().Any(IsRunning);
        return _watchedAppRunning;

        static bool IsRunning(string name)
        {
            var processes = Process.GetProcessesByName(name);
            foreach (var process in processes)
                process.Dispose();
            return processes.Length > 0;
        }
    }

    private void UpdateTexts(DateTime now)
    {
        var decision = _decision;
        (Headline, Detail) = decision.State switch
        {
            PresenceState.Active when decision.IsBoosted =>
                ("Boosted: you're staying green", $"The boost ends {When(decision.NextChange, now)}."),
            PresenceState.Active when decision.NextChange is not null =>
                ("You're staying green", $"Work hours end {When(decision.NextChange, now)}."),
            PresenceState.Active =>
                ("You're staying green", "Your PC stays awake and your status stays available."),
            PresenceState.Disabled =>
                ("KeepGreen is off", "Flip the switch or press Ctrl + Alt + G to turn it on."),
            PresenceState.OffSchedule => ("Outside your work hours", decision.NextChange is null
                ? "No work hours are set. Pick some days on the Schedule page."
                : $"Turns on by itself {When(decision.NextChange, now)}."),
            PresenceState.DayOff =>
                ("Day off. Enjoy it!", $"Back to work {When(decision.NextChange, now)}."),
            PresenceState.Break =>
                ("On a lunch break", $"Your status can show Away until {When(decision.NextChange, now)}."),
            PresenceState.Locked =>
                ("Paused while your PC is locked", "Starts again as soon as you unlock."),
            PresenceState.OnBattery =>
                ("Paused on battery power", "Starts again when you plug in."),
            PresenceState.LowBattery =>
                ("Paused: battery is low", "Starts again when you plug in."),
            PresenceState.WaitingForApp =>
                ("Waiting for your apps", $"Starts when {string.Join(" or ", _settings.WatchedAppNames().Take(3))} is running."),
            _ => ("", ""),
        };

        ScheduleSummary = BuildScheduleSummary(now);

        // One notification refreshes every dashboard binding; cheap at one tick per second.
        OnPropertyChanged(string.Empty);
    }

    private string BuildScheduleSummary(DateTime now)
    {
        if (!_settings.UseSchedule)
            return "Schedule is off: KeepGreen works whenever its switch is on.";

        var status = WorkSchedule.Evaluate(_settings, now);
        return status.State switch
        {
            PresenceState.Active => $"Work hours right now. They end {When(status.NextChange, now)}.",
            PresenceState.Break => $"Lunch break right now. Back {When(status.NextChange, now)}.",
            _ when status.NextChange is null => "No work hours set yet. Tick at least one day.",
            _ => $"Next work hours start {When(status.NextChange, now)}.",
        };
    }

    private static string When(DateTime? moment, DateTime now) => moment is { } value ? Humanize.When(value, now) : "soon";

    private void SetBoost(DateTime? until)
    {
        _boostUntil = until;
        Tick();
    }

    private double NextThreshold()
    {
        double interval = _settings.IntervalSeconds;
        return _settings.RandomizeInterval ? interval * (0.8 + (0.4 * Random.Shared.NextDouble())) : interval;
    }

    private void RollOverDay(DateTime now)
    {
        var today = DateOnly.FromDateTime(now);
        if (_stats.Date == today)
            return;

        _stats = new DailyStats { Date = today };
        SaveStats();
    }

    private void SaveStats()
    {
        _lastStatsSave = DateTime.Now;
        try
        {
            _store.SaveStats(_stats);
        }
        catch (IOException)
        {
            // Stats are nice to have; a locked file must never stop the engine.
        }
    }

    private void OnSettingsChanged(object? sender, PropertyChangedEventArgs e)
    {
        switch (e.PropertyName)
        {
            case nameof(AppSettings.IntervalSeconds) or nameof(AppSettings.RandomizeInterval):
                _thresholdSeconds = NextThreshold();
                break;
            case nameof(AppSettings.OnlyWhenAppsRunning) or nameof(AppSettings.WatchedApps):
                _lastAppScan = DateTime.MinValue;
                break;
            case nameof(AppSettings.IsEnabled) when !_settings.IsEnabled:
                _boostUntil = null;
                break;
        }

        Tick();
    }

    private void OnSessionSwitch(object? sender, SessionSwitchEventArgs e)
    {
        if (e.Reason == SessionSwitchReason.SessionLock)
            _isLocked = true;
        else if (e.Reason == SessionSwitchReason.SessionUnlock)
            _isLocked = false;
    }

    private void OnPowerModeChanged(object? sender, PowerModeChangedEventArgs e)
    {
        if (e.Mode != PowerModes.Resume)
            return;

        // After sleep, restart the timer and don't count the time asleep as green time.
        _timer.Dispatcher.InvokeAsync(() =>
        {
            _timer.Stop();
            _lastTick = DateTime.Now;
            _holdingAwake = false;
            Tick();
            _timer.Start();
        });
    }
}
