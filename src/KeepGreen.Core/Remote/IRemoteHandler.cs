namespace KeepGreen.Core.Remote;

/// <summary>
/// What the remote server asks of the app. Calls arrive on server threads, so the app
/// moves the work to its own thread before touching settings or the engine.
/// </summary>
public interface IRemoteHandler
{
    /// <summary>Read from server threads, so it should never change.</summary>
    RemoteIdentity Identity { get; }

    Task<RemoteStatus> GetStatusAsync(CancellationToken cancellationToken);

    /// <summary>Flips the master switch.</summary>
    Task SetEnabledAsync(bool enabled, CancellationToken cancellationToken);

    /// <summary>Starts a boost of 1 to 720 minutes; the server has already checked the range.</summary>
    Task BoostAsync(int minutes, CancellationToken cancellationToken);

    Task BoostUntilEndOfWorkdayAsync(CancellationToken cancellationToken);

    Task CancelBoostAsync(CancellationToken cancellationToken);
}
