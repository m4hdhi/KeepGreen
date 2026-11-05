#if DEBUG
using System.IO;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using KeepGreen.Core;
using KeepGreen.Services;
using Wpf.Ui.Appearance;

namespace KeepGreen;

/// <summary>
/// Debug-only: <c>KeepGreen.exe --screenshots docs</c> renders every page to PNG for the README.
/// Uses sample data in a temporary folder, so it never touches real settings or the screen.
/// </summary>
internal static class DocsScreenshots
{
    private static readonly (string Name, double Height)[] Pages = [("dashboard", 780), ("schedule", 1000), ("behavior", 1000)];

    public static async void Run(Application app, string outputFolder)
    {
        var dataFolder = Path.Combine(Path.GetTempPath(), "KeepGreen.Docs", Guid.NewGuid().ToString("N"));
        var store = new SettingsStore(dataFolder);
        var today = DateOnly.FromDateTime(DateTime.Now);
        var settings = new AppSettings { UseSchedule = false, LunchBreakEnabled = true, StartWithWindows = true };
        settings.Normalize(today);
        settings.DaysOff.Add(NextOccurrence(today, 12, 24));
        settings.DaysOff.Add(NextOccurrence(today, 12, 31));
        store.SaveStats(new DailyStats
        {
            Date = today,
            Nudges = 87,
            ActiveSeconds = new TimeSpan(6, 12, 0).TotalSeconds,
            LastNudge = DateTime.Today.AddHours(14).AddMinutes(32),
        });

        ApplicationThemeManager.Apply(ApplicationTheme.Dark, Wpf.Ui.Controls.WindowBackdropType.Mica, false);
        ApplicationAccentColorManager.Apply(StatusPalette.Green, ApplicationTheme.Dark);

        var engine = new PresenceEngine(settings, store);
        var viewModel = new MainViewModel(settings, engine, store)
        {
            HotkeyStatus = "Ready. Press Ctrl + Alt + G anywhere to turn KeepGreen on or off.",
            FolderDisplay = @"%APPDATA%\KeepGreen",
        };
        var window = new MainWindow(viewModel)
        {
            WindowStartupLocation = WindowStartupLocation.Manual,
            Left = -20000,
            Top = 0,
            ShowActivated = false,
            ShowInTaskbar = false,
        };
        window.Show();
        engine.Start();

        Directory.CreateDirectory(outputFolder);
        for (var page = 0; page < Pages.Length; page++)
        {
            // The dashboard shows the always-on state; the other pages read better with the schedule on.
            settings.UseSchedule = page != 0;
            window.Height = Pages[page].Height;
            window.Navigate(page);
            await Task.Delay(700);
            await Dispatcher.Yield(DispatcherPriority.ContextIdle);
            Save((FrameworkElement)window.Content, window, Path.Combine(outputFolder, $"screenshot-{Pages[page].Name}.png"));
        }

        window.Close();
        engine.Dispose();
        Directory.Delete(dataFolder, recursive: true);
        app.Shutdown();
    }

    private static void Save(FrameworkElement content, Window window, string path)
    {
        const double scale = 2;
        var size = new Size(content.ActualWidth, content.ActualHeight);
        var visual = new DrawingVisual();
        using (var context = visual.RenderOpen())
        {
            // Mica can't be captured off-screen, so paint the theme's solid background behind the content.
            var background = window.TryFindResource("ApplicationBackgroundBrush") as Brush ?? Brushes.Black;
            context.DrawRectangle(background, null, new Rect(size));
            context.DrawRectangle(new VisualBrush(content), null, new Rect(size));
        }

        var bitmap = new RenderTargetBitmap((int)(size.Width * scale), (int)(size.Height * scale), 96 * scale, 96 * scale, PixelFormats.Pbgra32);
        bitmap.Render(visual);
        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(bitmap));
        using var file = File.Create(path);
        encoder.Save(file);
    }

    private static DateOnly NextOccurrence(DateOnly today, int month, int day)
    {
        var date = new DateOnly(today.Year, month, day);
        return date >= today ? date : date.AddYears(1);
    }
}
#endif
