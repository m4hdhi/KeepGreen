using System.Windows.Threading;
using KeepGreen.Core;
using KeepGreen.Core.Remote;

namespace KeepGreen.Services;

/// <summary>
/// Answers the phone remote. Requests arrive on server threads, so every call hops to the UI thread,
/// where the engine and settings live, and waits for the result there.
/// </summary>
internal sealed class RemoteHandler(Dispatcher dispatcher, AppSettings settings, PresenceEngine engine) : IRemoteHandler
{
    public RemoteIdentity Identity { get; } = new(Environment.MachineName, "windows", App.InformationalVersion);

    public async Task<RemoteStatus> GetStatusAsync(CancellationToken cancellationToken) =>
        await dispatcher.InvokeAsync(BuildStatus, DispatcherPriority.Normal, cancellationToken);

    public async Task SetEnabledAsync(bool enabled, CancellationToken cancellationToken) =>
        await dispatcher.InvokeAsync(() => { settings.IsEnabled = enabled; }, DispatcherPriority.Normal, cancellationToken);

    public async Task BoostAsync(int minutes, CancellationToken cancellationToken) =>
        await dispatcher.InvokeAsync(() => engine.Boost(TimeSpan.FromMinutes(minutes)), DispatcherPriority.Normal, cancellationToken);

    public async Task BoostUntilEndOfWorkdayAsync(CancellationToken cancellationToken) =>
        await dispatcher.InvokeAsync(engine.BoostUntilEndOfWorkday, DispatcherPriority.Normal, cancellationToken);

    public async Task CancelBoostAsync(CancellationToken cancellationToken) =>
        await dispatcher.InvokeAsync(engine.CancelBoost, DispatcherPriority.Normal, cancellationToken);

    private RemoteStatus BuildStatus() => new()
    {
        Name = Identity.Name,
        Platform = Identity.Platform,
        Version = Identity.Version,
        State = engine.State,
        IsActive = engine.IsActive,
        IsEnabled = settings.IsEnabled,
        IsBoosted = engine.IsBoosted,

        // Local time, so the offset tells the phone which time zone the PC is in.
        BoostUntil = engine.BoostUntil is { } until ? new DateTimeOffset(until) : null,
        Headline = engine.Headline,
        Detail = engine.Detail,
        IdleSeconds = engine.IdleSeconds,
        NudgesToday = engine.NudgesToday,
        GreenSecondsToday = engine.GreenSecondsToday,
    };
}
