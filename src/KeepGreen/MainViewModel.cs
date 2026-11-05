using System.Reflection;
using KeepGreen.Core;
using KeepGreen.Services;

namespace KeepGreen;

internal sealed class MainViewModel : ObservableObject
{
    private readonly string? _folderDisplay;
    private string _hotkeyStatus = "";

    public MainViewModel(AppSettings settings, PresenceEngine engine, SettingsStore store)
    {
        Settings = settings;
        Engine = engine;
        Store = store;
    }

    public AppSettings Settings { get; }

    public PresenceEngine Engine { get; }

    public SettingsStore Store { get; }

    /// <summary>The settings folder as people write it, e.g. %APPDATA%\KeepGreen.</summary>
    public string FolderDisplay
    {
        get => _folderDisplay ?? Store.Folder.Replace(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "%APPDATA%", StringComparison.OrdinalIgnoreCase);
        init => _folderDisplay = value;
    }

    /// <summary>Every quarter hour of the day, for the time pickers.</summary>
    public IReadOnlyList<TimeOnly> TimeChoices { get; } =
        Enumerable.Range(0, 96).Select(i => new TimeOnly(i / 4, i % 4 * 15)).ToArray();

    public IReadOnlyList<int> BatteryChoices { get; } = [10, 15, 20, 25, 30, 40, 50];

    public IReadOnlyList<ThemePreference> Themes { get; } = Enum.GetValues<ThemePreference>();

    public string Version { get; } = "Version " +
        (Assembly.GetExecutingAssembly().GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion ?? "1.0.0");

    public string HotkeyStatus
    {
        get => _hotkeyStatus;
        set => SetProperty(ref _hotkeyStatus, value);
    }
}
