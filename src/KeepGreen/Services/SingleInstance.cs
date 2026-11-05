namespace KeepGreen.Services;

/// <summary>Keeps one copy running. Starting it again just brings the open window forward.</summary>
internal sealed class SingleInstance : IDisposable
{
    private const string MutexName = @"Local\KeepGreen-3F6A2C1E-instance";
    private const string ShowEventName = @"Local\KeepGreen-3F6A2C1E-show";

    private readonly Mutex _mutex;
    private readonly EventWaitHandle _showEvent;
    private readonly RegisteredWaitHandle _registration;

    private SingleInstance(Mutex mutex, Action onShowRequested)
    {
        _mutex = mutex;
        _showEvent = new EventWaitHandle(false, EventResetMode.AutoReset, ShowEventName);
        _registration = ThreadPool.RegisterWaitForSingleObject(
            _showEvent, (_, _) => onShowRequested(), null, Timeout.Infinite, executeOnlyOnce: false);
    }

    /// <returns>The instance guard, or null when another copy is running (it has been asked to show itself).</returns>
    public static SingleInstance? TryStart(Action onShowRequested)
    {
        var mutex = new Mutex(initiallyOwned: true, MutexName, out var createdNew);
        if (createdNew)
            return new SingleInstance(mutex, onShowRequested);

        mutex.Dispose();
        if (EventWaitHandle.TryOpenExisting(ShowEventName, out var showEvent))
        {
            showEvent.Set();
            showEvent.Dispose();
        }

        return null;
    }

    public void Dispose()
    {
        _registration.Unregister(null);
        _showEvent.Dispose();
        _mutex.ReleaseMutex();
        _mutex.Dispose();
    }
}
