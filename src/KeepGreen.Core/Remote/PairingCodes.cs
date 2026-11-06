using System.Globalization;
using System.Security.Cryptography;
using System.Text;

namespace KeepGreen.Core.Remote;

public enum PairingResult
{
    Paired,

    /// <summary>The code is wrong or has expired.</summary>
    WrongCode,

    /// <summary>Too many wrong codes; pairing is closed for a minute.</summary>
    LockedOut,
}

public readonly record struct PairingCode(string Code, DateTimeOffset ExpiresAt);

/// <summary>
/// The 6-digit code a phone types to pair. A code lasts 10 minutes and is replaced when it expires,
/// after a successful pairing, or after 5 wrong tries, which also close pairing for 60 seconds.
/// Safe to use from any thread.
/// </summary>
public sealed class PairingCodes
{
    public const int MaxWrongAttempts = 5;

    public static readonly TimeSpan Lifetime = TimeSpan.FromMinutes(10);
    public static readonly TimeSpan Lockout = TimeSpan.FromSeconds(60);

    private readonly TimeProvider _time;
    private readonly Lock _gate = new();
    private string _code = "";
    private DateTimeOffset _expiresAt;
    private DateTimeOffset _lockedUntil;
    private int _wrongAttempts;

    public PairingCodes(TimeProvider? time = null)
    {
        _time = time ?? TimeProvider.System;
        lock (_gate)
            Replace(_time.GetUtcNow());
    }

    /// <summary>The code to show right now. Reading it replaces an expired code.</summary>
    public PairingCode Current
    {
        get
        {
            lock (_gate)
            {
                var now = _time.GetUtcNow();
                if (now >= _expiresAt)
                    Replace(now);
                return new PairingCode(_code, _expiresAt);
            }
        }
    }

    /// <summary>When pairing opens again after too many wrong codes, or null while it's open.</summary>
    public DateTimeOffset? LockedUntil
    {
        get
        {
            lock (_gate)
                return _lockedUntil > _time.GetUtcNow() ? _lockedUntil : null;
        }
    }

    /// <summary>Throws the current code away, for the "New code" button.</summary>
    public void Renew()
    {
        lock (_gate)
            Replace(_time.GetUtcNow());
    }

    public PairingResult TryPair(string? code)
    {
        lock (_gate)
        {
            var now = _time.GetUtcNow();
            if (_lockedUntil > now)
                return PairingResult.LockedOut;
            if (now >= _expiresAt)
                Replace(now);

            // Spaces are allowed, since the code is shown as "123 456".
            var typed = string.Concat((code ?? "").Where(c => !char.IsWhiteSpace(c)));
            if (CryptographicOperations.FixedTimeEquals(Encoding.ASCII.GetBytes(typed), Encoding.ASCII.GetBytes(_code)))
            {
                Replace(now);
                return PairingResult.Paired;
            }

            if (++_wrongAttempts >= MaxWrongAttempts)
            {
                Replace(now);
                _lockedUntil = now + Lockout;
            }

            return PairingResult.WrongCode;
        }
    }

    private void Replace(DateTimeOffset now)
    {
        var previous = _code;
        do
            _code = RandomNumberGenerator.GetInt32(1_000_000).ToString("D6", CultureInfo.InvariantCulture);
        while (_code == previous);

        _expiresAt = now + Lifetime;
        _wrongAttempts = 0;
    }
}
