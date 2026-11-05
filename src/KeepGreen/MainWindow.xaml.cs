using System.Diagnostics;
using System.IO;
using System.Windows;
using KeepGreen.Core;
using Wpf.Ui.Controls;

namespace KeepGreen;

public partial class MainWindow : FluentWindow
{
    private const string RepositoryUrl = "https://github.com/m4hdhi/KeepGreen";

    private static readonly DayOfWeek[] Weekdays =
        [DayOfWeek.Monday, DayOfWeek.Tuesday, DayOfWeek.Wednesday, DayOfWeek.Thursday, DayOfWeek.Friday];

    private readonly MainViewModel _viewModel;

    internal MainWindow(MainViewModel viewModel)
    {
        _viewModel = viewModel;
        DataContext = viewModel;
        InitializeComponent();
        DayOffPicker.DisplayDateStart = DateTime.Today;
        ShowPage(0);
    }

    internal void Navigate(int page) => Nav.SelectedIndex = page;

    private void Nav_SelectionChanged(object sender, System.Windows.Controls.SelectionChangedEventArgs e)
    {
        // Fires once while the XAML is still loading, before the pages exist.
        if (SettingsPage is null)
            return;
        ShowPage(Nav.SelectedIndex);
    }

    private void ShowPage(int index)
    {
        FrameworkElement[] pages = [DashboardPage, SchedulePage, BehaviorPage, SettingsPage];
        for (var i = 0; i < pages.Length; i++)
            pages[i].Visibility = i == index ? Visibility.Visible : Visibility.Collapsed;
    }

    private void Boost_Click(object sender, RoutedEventArgs e)
    {
        var tag = (string)((FrameworkElement)sender).Tag;
        if (tag == "eod")
            _viewModel.Engine.BoostUntilEndOfWorkday();
        else
            _viewModel.Engine.Boost(TimeSpan.FromMinutes(int.Parse(tag, System.Globalization.CultureInfo.InvariantCulture)));
    }

    private void CancelBoost_Click(object sender, RoutedEventArgs e) => _viewModel.Engine.CancelBoost();

    private async void SelfTest_Click(object sender, RoutedEventArgs e)
    {
        var (ok, message) = await _viewModel.Engine.RunSelfTestAsync();
        TestResultBar.Severity = ok ? InfoBarSeverity.Success : InfoBarSeverity.Error;
        TestResultBar.Message = message;
        TestResultBar.IsOpen = true;
    }

    private void Preset_Click(object sender, RoutedEventArgs e)
    {
        var (days, start, end) = ((FrameworkElement)sender).Tag switch
        {
            "weekdays-9-17" => (Weekdays, new TimeOnly(9, 0), new TimeOnly(17, 0)),
            "weekdays-8-18" => (Weekdays, new TimeOnly(8, 0), new TimeOnly(18, 0)),
            _ => (AppSettings.WeekOrder, new TimeOnly(8, 0), new TimeOnly(20, 0)),
        };

        foreach (var day in _viewModel.Settings.Week)
        {
            day.Enabled = days.Contains(day.Day);
            day.Start = start;
            day.End = end;
        }

        _viewModel.Settings.UseSchedule = true;
    }

    private void AddDayOff_Click(object sender, RoutedEventArgs e)
    {
        if (DayOffPicker.SelectedDate is not { } picked)
            return;

        var day = DateOnly.FromDateTime(picked);
        var daysOff = _viewModel.Settings.DaysOff;
        if (!daysOff.Contains(day))
        {
            var index = 0;
            while (index < daysOff.Count && daysOff[index] < day)
                index++;
            daysOff.Insert(index, day);
        }

        DayOffPicker.SelectedDate = null;
    }

    private void RemoveDayOff_Click(object sender, RoutedEventArgs e)
    {
        if (((FrameworkElement)sender).Tag is DateOnly day)
            _viewModel.Settings.DaysOff.Remove(day);
    }

    private void OpenDataFolder_Click(object sender, RoutedEventArgs e)
    {
        Directory.CreateDirectory(_viewModel.Store.Folder);
        Process.Start("explorer.exe", $"\"{_viewModel.Store.Folder}\"");
    }

    private void OpenRepo_Click(object sender, RoutedEventArgs e) =>
        Process.Start(new ProcessStartInfo(RepositoryUrl) { UseShellExecute = true });
}
