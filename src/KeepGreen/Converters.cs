using System.Globalization;
using System.Windows;
using System.Windows.Data;
using System.Windows.Media;
using KeepGreen.Core;

namespace KeepGreen;

internal enum StatusTone
{
    Green,
    Amber,
    Gray,
}

/// <summary>The three status colours, shared by the dashboard and the tray icon.</summary>
internal static class StatusPalette
{
    public static readonly Color Green = Color.FromRgb(0x22, 0xC5, 0x5E);
    public static readonly Color Amber = Color.FromRgb(0xF5, 0x9E, 0x0B);
    public static readonly Color Gray = Color.FromRgb(0x94, 0xA3, 0xB8);

    public static StatusTone ToneOf(PresenceState state) => state switch
    {
        PresenceState.Active => StatusTone.Green,
        PresenceState.Disabled => StatusTone.Gray,
        _ => StatusTone.Amber,
    };

    public static Color ColorOf(StatusTone tone) => tone switch
    {
        StatusTone.Green => Green,
        StatusTone.Amber => Amber,
        _ => Gray,
    };
}

/// <summary>Paints a <see cref="PresenceState"/> or a <see cref="StatusTone"/> in the status colours.</summary>
public sealed class StateToBrushConverter : IValueConverter
{
    private static readonly Dictionary<StatusTone, SolidColorBrush> Palette =
        Enum.GetValues<StatusTone>().ToDictionary(tone => tone, tone =>
        {
            var brush = new SolidColorBrush(StatusPalette.ColorOf(tone));
            brush.Freeze();
            return brush;
        });

    public object Convert(object value, Type targetType, object parameter, CultureInfo culture) => Palette[value switch
    {
        PresenceState state => StatusPalette.ToneOf(state),
        StatusTone tone => tone,
        _ => StatusTone.Gray,
    }];

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) =>
        throw new NotSupportedException();
}

/// <summary>Binds a group of radio buttons to one enum value; the parameter is the member name.</summary>
public sealed class EnumToBoolConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture) =>
        string.Equals(value?.ToString(), parameter as string, StringComparison.Ordinal);

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) =>
        value is true && parameter is string name ? Enum.Parse(targetType, name) : Binding.DoNothing;
}

/// <summary>Visible only when a count is zero, for "nothing here yet" messages.</summary>
public sealed class ZeroToVisibleConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture) =>
        value is 0 ? Visibility.Visible : Visibility.Collapsed;

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) =>
        throw new NotSupportedException();
}

public sealed class InverseBoolToVisibilityConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture) =>
        value is true ? Visibility.Collapsed : Visibility.Visible;

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) =>
        throw new NotSupportedException();
}
