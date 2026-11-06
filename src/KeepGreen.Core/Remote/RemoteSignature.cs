using System.Globalization;
using System.Security.Cryptography;
using System.Text;

namespace KeepGreen.Core.Remote;

public enum SignatureCheck
{
    Valid,

    /// <summary>The time or signature header is missing or malformed.</summary>
    Missing,

    BadSignature,

    /// <summary>The signature is right, but the phone's clock is too far from ours.</summary>
    ClockSkew,
}

/// <summary>Signs and checks phone requests as described in docs/remote-api.md.</summary>
public static class RemoteSignature
{
    public const string TimeHeader = "X-KeepGreen-Time";
    public const string SignatureHeader = "X-KeepGreen-Signature";

    public static readonly TimeSpan MaxClockSkew = TimeSpan.FromSeconds(120);

    /// <summary>A new shared key: 16 random bytes as 32 lowercase hex characters.</summary>
    public static string NewKey() => Convert.ToHexStringLower(RandomNumberGenerator.GetBytes(16));

    public static bool IsValidKey(string? key) => key is { Length: 32 } && key.All(char.IsAsciiHexDigitLower);

    /// <summary>The signed text: method, path, time and body, joined by newlines.</summary>
    public static string Message(string method, string path, string time, string body) =>
        $"{method}\n{path}\n{time}\n{body}";

    /// <summary>Lowercase hex HMAC-SHA256 of the message. The key's text is the HMAC key, not its decoded bytes.</summary>
    public static string Compute(string key, string method, string path, string time, string body) =>
        Convert.ToHexStringLower(Hash(key, method, path, time, body));

    public static SignatureCheck Verify(
        string key, string method, string path, string? time, string body, string? signature, DateTimeOffset now)
    {
        if (string.IsNullOrEmpty(time) || string.IsNullOrEmpty(signature) ||
            !long.TryParse(time, NumberStyles.None, CultureInfo.InvariantCulture, out var seconds) ||
            signature.Length != 64 || !signature.All(char.IsAsciiHexDigit))
        {
            return SignatureCheck.Missing;
        }

        // Anyone could sign with an empty or made-up key, so only a real one counts.
        if (!IsValidKey(key))
            return SignatureCheck.BadSignature;

        // Compared in constant time, so the answer's timing says nothing about how close a guess was.
        var expected = Hash(key, method, path, time, body);
        if (!CryptographicOperations.FixedTimeEquals(expected, Convert.FromHexString(signature)))
            return SignatureCheck.BadSignature;

        return Math.Abs(now.ToUnixTimeSeconds() - seconds) > MaxClockSkew.TotalSeconds
            ? SignatureCheck.ClockSkew
            : SignatureCheck.Valid;
    }

    private static byte[] Hash(string key, string method, string path, string time, string body) =>
        HMACSHA256.HashData(Encoding.UTF8.GetBytes(key), Encoding.UTF8.GetBytes(Message(method, path, time, body)));
}
