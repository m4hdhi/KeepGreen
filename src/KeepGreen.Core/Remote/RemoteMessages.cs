using System.Globalization;
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace KeepGreen.Core.Remote;

/// <summary>Who this desktop is, as phones see it.</summary>
public sealed record RemoteIdentity(string Name, string Platform, string Version);

/// <summary>The status object every signed endpoint returns. Property order matches the spec.</summary>
public sealed record RemoteStatus
{
    public string Name { get; init; } = "";

    public string Platform { get; init; } = "";

    public string Version { get; init; } = "";

    public PresenceState State { get; init; }

    public bool IsActive { get; init; }

    public bool IsEnabled { get; init; }

    public bool IsBoosted { get; init; }

    /// <summary>Written as ISO 8601 with offset and whole seconds, or null.</summary>
    public DateTimeOffset? BoostUntil { get; init; }

    public string Headline { get; init; } = "";

    public string Detail { get; init; } = "";

    public long IdleSeconds { get; init; }

    public int NudgesToday { get; init; }

    public long GreenSecondsToday { get; init; }
}

public sealed record RemotePing(string App, int Api, string Name, string Platform, string Version);

public sealed record RemotePairRequest(string? Code, string? Device);

public sealed record RemotePairResponse(string Key, string Name, string Platform, string Version);

public sealed record RemoteEnabledRequest(bool? Enabled);

public sealed record RemoteBoostRequest(int? Minutes, bool? UntilEndOfWorkday);

public sealed record RemoteError(string Error);

/// <summary>The JSON settings of the remote API: camelCase names and enums as their names.</summary>
public static class RemoteJson
{
    public static readonly JsonSerializerOptions Options = new()
    {
        // Phones read this, never a browser page, so "You're" and "+04:00" can stay as they are.
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = true,
        Converters = { new JsonStringEnumConverter(), new WholeSecondsConverter() },
    };

    public static byte[] Serialize<T>(T value) => JsonSerializer.SerializeToUtf8Bytes(value, Options);

    public static T? Deserialize<T>(string json) => JsonSerializer.Deserialize<T>(json, Options);

    /// <summary>
    /// ISO 8601 without fractions, e.g. "2026-11-05T14:30:00+04:00". Some phone date parsers
    /// reject fractional seconds, which System.Text.Json would otherwise write.
    /// </summary>
    private sealed class WholeSecondsConverter : JsonConverter<DateTimeOffset>
    {
        private const string Format = "yyyy-MM-dd'T'HH:mm:sszzz";

        public override DateTimeOffset Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options) =>
            DateTimeOffset.Parse(reader.GetString()!, CultureInfo.InvariantCulture);

        public override void Write(Utf8JsonWriter writer, DateTimeOffset value, JsonSerializerOptions options) =>
            writer.WriteStringValue(value.ToString(Format, CultureInfo.InvariantCulture));
    }
}
