namespace KeepGreen.Core;

public enum PresenceState
{
    /// <summary>Keeping the PC awake and the status green.</summary>
    Active,

    /// <summary>The master switch is off.</summary>
    Disabled,

    OffSchedule,
    DayOff,
    Break,
    Locked,
    OnBattery,
    LowBattery,
    WaitingForApp,
}

/// <summary>A snapshot of the machine, gathered by the app once per tick.</summary>
public readonly record struct PresenceContext(
    DateTime Now,
    bool IsLocked,
    bool IsOnBattery,
    int BatteryPercent,
    bool IsWatchedAppRunning);

public readonly record struct PresenceDecision(PresenceState State, bool IsBoosted, DateTime? NextChange)
{
    public bool IsActive => State == PresenceState.Active;
}

/// <summary>Decides whether KeepGreen should be working right now. Pure, so it is fully unit-tested.</summary>
public static class PresencePolicy
{
    public static PresenceDecision Evaluate(AppSettings settings, in PresenceContext context, DateTime? boostUntil)
    {
        // A boost beats the master switch and the schedule, but never the safety pauses below.
        var boosted = boostUntil > context.Now;
        var nextChange = boosted ? boostUntil : null;

        if (!boosted)
        {
            if (!settings.IsEnabled)
                return new PresenceDecision(PresenceState.Disabled, false, null);

            if (settings.UseSchedule)
            {
                var schedule = WorkSchedule.Evaluate(settings, context.Now);
                if (schedule.State != PresenceState.Active)
                    return new PresenceDecision(schedule.State, false, schedule.NextChange);
                nextChange = schedule.NextChange;
            }
        }

        if (settings.PauseWhenLocked && context.IsLocked)
            return new PresenceDecision(PresenceState.Locked, boosted, nextChange);

        if (context.IsOnBattery)
        {
            if (settings.PauseOnBattery)
                return new PresenceDecision(PresenceState.OnBattery, boosted, nextChange);

            var batteryKnown = context.BatteryPercent >= 0;
            if (settings.PauseOnLowBattery && batteryKnown && context.BatteryPercent < settings.LowBatteryPercent)
                return new PresenceDecision(PresenceState.LowBattery, boosted, nextChange);
        }

        if (settings.OnlyWhenAppsRunning && !context.IsWatchedAppRunning)
            return new PresenceDecision(PresenceState.WaitingForApp, boosted, nextChange);

        return new PresenceDecision(PresenceState.Active, boosted, nextChange);
    }
}
