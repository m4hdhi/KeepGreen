using System.ComponentModel;
using System.IO;
using System.Security;
using System.Windows;
using System.Windows.Threading;
using KeepGreen.Core;
using KeepGreen.Services;
using Microsoft.Win32;
using Wpf.Ui.Appearance;

namespace KeepGreen;

public partial class App : Application
{
    private readonly DispatcherTimer _saveTimer = new() { Interval = TimeSpan.FromMilliseconds(600) };
    private SingleInstance? _singleInstance;
    private SettingsStore? _store;
    private AppSettings? _settings;
    private PresenceEngine? _engine;
    private MainViewModel? _viewModel;
    private MainWindow? _window;
    private TrayIconService? _tray;
    private HotkeyService? _hotkey;
    private ApplicationTheme? _appliedTheme;
    private bool _quitting;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

#if DEBUG
        var screenshots = Array.IndexOf(e.Args, "--screenshots");
        if (screenshots >= 0 && screenshots + 1 < e.Args.Length)
        {
            DocsScreenshots.Run(this, e.Args[screenshots + 1]);
            return;
        }
#endif

        _singleInstance = SingleInstance.TryStart(() => Dispatcher.InvokeAsync(ShowMainWindow));
        if (_singleInstance is null)
        {
            Shutdown();
            return;
        }

        DispatcherUnhandledException += OnUnhandledException;

        _store = new SettingsStore();
        _settings = _store.LoadSettings(DateOnly.FromDateTime(DateTime.Now));
        _settings.StartWithWindows = StartupRegistration.IsRegistered();
        _settings.TrackChanges();

        _engine = new PresenceEngine(_settings, _store);
        _viewModel = new MainViewModel(_settings, _engine, _store);
        _window = new MainWindow(_viewModel);
        _window.Closing += OnWindowClosing;
        ApplyTheme();
        SystemEvents.UserPreferenceChanged += OnUserPreferenceChanged;

        _tray = new TrayIconService(_engine, _settings, ShowMainWindow, Quit);
        _hotkey = new HotkeyService(_window, ToggleFromHotkey);
        UpdateHotkey();

        _saveTimer.Tick += (_, _) =>
        {
            _saveTimer.Stop();
            SaveSettings();
        };
        _settings.Changed += (_, _) =>
        {
            _saveTimer.Stop();
            _saveTimer.Start();
        };
        _settings.PropertyChanged += OnSettingChanged;
        _engine.StateChanged += OnPresenceChanged;
        _engine.Start();

        var launchedAtSignIn = e.Args.Any(arg => string.Equals(arg, "--tray", StringComparison.OrdinalIgnoreCase));
        if (!(launchedAtSignIn && _settings.StartInTray))
            ShowMainWindow();
    }

    protected override void OnExit(ExitEventArgs e)
    {
        SystemEvents.UserPreferenceChanged -= OnUserPreferenceChanged;
        _engine?.Dispose();
        _hotkey?.Dispose();
        _tray?.Dispose();
        SaveSettings();
        _singleInstance?.Dispose();
        base.OnExit(e);
    }

    private void ShowMainWindow()
    {
        if (_window is null)
            return;

        _window.Show();
        if (_window.WindowState == WindowState.Minimized)
            _window.WindowState = WindowState.Normal;
        _window.Activate();
    }

    private void Quit()
    {
        _quitting = true;
        _window?.Close();
        Shutdown();
    }

    private void OnWindowClosing(object? sender, CancelEventArgs e)
    {
        if (_quitting || _settings is null)
            return;

        // Closing the window only hides it; KeepGreen keeps working from the tray.
        e.Cancel = true;
        _window?.Hide();
        if (!_settings.TrayHintShown)
        {
            _settings.TrayHintShown = true;
            _tray?.ShowNotification("KeepGreen is still running", "It keeps working from the tray. Right-click the dot to quit.");
        }
    }

    private void ToggleFromHotkey()
    {
        if (_settings is null || _engine is null)
            return;

        _settings.IsEnabled = !_settings.IsEnabled;
        _tray?.ShowNotification(_settings.IsEnabled ? "KeepGreen is on" : "KeepGreen is off", _engine.Headline);
    }

    private void UpdateHotkey()
    {
        if (_hotkey is null || _settings is null || _viewModel is null)
            return;

        var registered = _hotkey.SetEnabled(_settings.HotkeyEnabled);
        _viewModel.HotkeyStatus = !_settings.HotkeyEnabled ? "The shortcut is turned off."
            : registered ? "Ready. Press Ctrl + Alt + G anywhere to turn KeepGreen on or off."
            : "Ctrl + Alt + G is already used by another app.";
    }

    private void OnSettingChanged(object? sender, PropertyChangedEventArgs e)
    {
        switch (e.PropertyName)
        {
            case nameof(AppSettings.Theme):
                ApplyTheme();
                break;
            case nameof(AppSettings.HotkeyEnabled):
                UpdateHotkey();
                break;
            case nameof(AppSettings.StartWithWindows):
                try
                {
                    StartupRegistration.Set(_settings!.StartWithWindows);
                }
                catch (Exception ex) when (ex is UnauthorizedAccessException or SecurityException or IOException)
                {
                    _tray?.ShowNotification("Couldn't change startup", ex.Message);
                }

                break;
        }
    }

    private void OnPresenceChanged(object? sender, PresenceTransition transition)
    {
        if (_settings is not { Notifications: true } || _engine is null)
            return;

        var (previous, current) = (transition.Previous, transition.Current);
        string? message = null;
        if (previous.IsBoosted && !current.IsBoosted)
            message = $"Your boost has ended. {_engine.Detail}";
        else if (current.IsActive && previous.State is PresenceState.OffSchedule or PresenceState.DayOff or PresenceState.Break)
            message = "Work hours started. KeepGreen is keeping you available.";
        else if (previous.IsActive && current.State is PresenceState.OffSchedule or PresenceState.DayOff)
            message = $"Work hours are over. {_engine.Detail}";
        else if (previous.IsActive && current.State == PresenceState.Break)
            message = $"Lunch break. {_engine.Detail}";

        if (message is not null)
            _tray?.ShowNotification("KeepGreen", message);
    }

    private void ApplyTheme()
    {
        if (_settings is null)
            return;

        var theme = _settings.Theme switch
        {
            ThemePreference.Light => ApplicationTheme.Light,
            ThemePreference.Dark => ApplicationTheme.Dark,
            _ => SystemUsesLightTheme() ? ApplicationTheme.Light : ApplicationTheme.Dark,
        };
        if (theme == _appliedTheme)
            return;

        _appliedTheme = theme;
        ApplicationThemeManager.Apply(theme, Wpf.Ui.Controls.WindowBackdropType.Mica, false);
        ApplicationAccentColorManager.Apply(StatusPalette.Green, theme);
    }

    private void OnUserPreferenceChanged(object? sender, UserPreferenceChangedEventArgs e)
    {
        if (_settings?.Theme == ThemePreference.System)
            Dispatcher.InvokeAsync(ApplyTheme);
    }

    private static bool SystemUsesLightTheme()
    {
        using var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
        return key?.GetValue("AppsUseLightTheme") is int value && value == 1;
    }

    private void SaveSettings()
    {
        if (_settings is null || _store is null)
            return;

        try
        {
            _store.SaveSettings(_settings);
        }
        catch (IOException)
        {
            // Retried on the next change; never crash over a busy settings file.
        }
    }

    private void OnUnhandledException(object sender, DispatcherUnhandledExceptionEventArgs e)
    {
        try
        {
            Directory.CreateDirectory(SettingsStore.DefaultFolder);
            File.AppendAllText(
                Path.Combine(SettingsStore.DefaultFolder, "crash.log"),
                $"[{DateTime.Now:O}] {e.Exception}{Environment.NewLine}{Environment.NewLine}");
        }
        catch (IOException)
        {
        }

        // Stay alive in the tray: a status keeper that quits silently is worse than one bad click.
        e.Handled = true;
    }
}
