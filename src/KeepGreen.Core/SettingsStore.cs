using System.Text.Json;
using System.Text.Json.Serialization;

namespace KeepGreen.Core;

/// <summary>Today's numbers for the dashboard. Reset at midnight.</summary>
public sealed class DailyStats
{
    public DateOnly Date { get; set; }

    public int Nudges { get; set; }

    public double ActiveSeconds { get; set; }

    public DateTime? LastNudge { get; set; }
}

/// <summary>Reads and writes settings and stats as JSON. Writes are atomic; a corrupt file is set aside.</summary>
public sealed class SettingsStore
{
    private static readonly JsonSerializerOptions Options = new()
    {
        WriteIndented = true,
        Converters = { new JsonStringEnumConverter() },
    };

    public SettingsStore(string? folder = null) => Folder = folder ?? DefaultFolder;

    public static string DefaultFolder =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "KeepGreen");

    public string Folder { get; }

    public string SettingsPath => Path.Combine(Folder, "settings.json");

    public string StatsPath => Path.Combine(Folder, "stats.json");

    public AppSettings LoadSettings(DateOnly today)
    {
        var settings = Read<AppSettings>(SettingsPath) ?? new AppSettings();
        settings.Normalize(today);
        return settings;
    }

    public void SaveSettings(AppSettings settings) => Write(SettingsPath, settings);

    public DailyStats LoadStats(DateOnly today)
    {
        var stats = Read<DailyStats>(StatsPath);
        return stats is not null && stats.Date == today ? stats : new DailyStats { Date = today };
    }

    public void SaveStats(DailyStats stats) => Write(StatsPath, stats);

    private static T? Read<T>(string path)
        where T : class
    {
        try
        {
            return File.Exists(path) ? JsonSerializer.Deserialize<T>(File.ReadAllText(path), Options) : null;
        }
        catch (JsonException)
        {
            // Keep the broken file for inspection and start fresh rather than crash at sign-in.
            File.Copy(path, path + ".broken", overwrite: true);
            return null;
        }
    }

    private static void Write<T>(string path, T value)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        var temp = path + ".tmp";
        File.WriteAllText(temp, JsonSerializer.Serialize(value, Options));
        File.Move(temp, path, overwrite: true);
    }
}
