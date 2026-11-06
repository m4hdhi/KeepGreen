using System.Globalization;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Text.Json;
using KeepGreen.Core;
using KeepGreen.Core.Remote;

// The key from the test vector in docs/remote-api.md.
const string TestKey = "00112233445566778899aabbccddeeff";

// 2 November 2026 is a Monday; 6 November is a Friday.
static DateTime On(int day, int hour, int minute = 0) => new(2026, 11, day, hour, minute, 0);

static AppSettings Defaults()
{
    var settings = new AppSettings();
    settings.Normalize(new DateOnly(2026, 11, 1));
    return settings;
}

static PresenceContext At(DateTime now, bool locked = false, bool onBattery = false, int battery = 100, bool appRunning = true) =>
    new(now, locked, onBattery, battery, appRunning);

static void Run(Func<Task> test) => test().GetAwaiter().GetResult();

static HttpClient NewClient(int port) =>
    new(new SocketsHttpHandler { UseProxy = false }) { BaseAddress = new Uri($"http://127.0.0.1:{port}/"), Timeout = TimeSpan.FromSeconds(5) };

// Listens on loopback only, so the tests never trigger the Windows firewall prompt.
static void WithServer(Func<RemoteServer, HttpClient, FakeRemoteHandler, PairingCodes, Task> test)
{
    var handler = new FakeRemoteHandler();
    var pairing = new PairingCodes();
    using var server = new RemoteServer(handler, pairing) { Key = TestKey };
    Assert.True(server.Start(0, IPAddress.Loopback), server.Error ?? "the server should start");
    Assert.Equal(RemoteServerState.Listening, server.State);
    using var client = NewClient(server.Port);
    Run(() => test(server, client, handler, pairing));
}

static HttpRequestMessage Unsigned(HttpMethod method, string path, string? body = null) =>
    new(method, path) { Content = body is null ? null : new StringContent(body, Encoding.UTF8, "application/json") };

static HttpRequestMessage Signed(HttpMethod method, string path, string? body = null, string key = TestKey, long? time = null)
{
    var stamp = (time ?? DateTimeOffset.UtcNow.ToUnixTimeSeconds()).ToString(CultureInfo.InvariantCulture);
    var request = Unsigned(method, path, body);
    request.Headers.Add(RemoteSignature.TimeHeader, stamp);
    request.Headers.Add(RemoteSignature.SignatureHeader, RemoteSignature.Compute(key, method.Method, path.Split('?')[0], stamp, body ?? ""));
    return request;
}

static async Task<(int Status, JsonElement Json)> SendAsync(HttpClient client, HttpRequestMessage request)
{
    using (request)
    {
        using var response = await client.SendAsync(request);
        using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        return ((int)response.StatusCode, json.RootElement.Clone());
    }
}

static async Task<string> SendRawAsync(int port, string text)
{
    using var tcp = new TcpClient();
    await tcp.ConnectAsync(IPAddress.Loopback, port);
    var stream = tcp.GetStream();
    await stream.WriteAsync(Encoding.ASCII.GetBytes(text));
    using var reader = new StreamReader(stream);
    return await reader.ReadToEndAsync();
}

static string WrongCode(string code) =>
    ((int.Parse(code, CultureInfo.InvariantCulture) + 1) % 1_000_000).ToString("D6", CultureInfo.InvariantCulture);

var tests = new (string Name, Action Run)[]
{
    ("Weekday inside work hours is active until the end", () =>
    {
        var status = WorkSchedule.Evaluate(Defaults(), On(2, 10));
        Assert.Equal(PresenceState.Active, status.State);
        Assert.Equal<DateTime?>(On(2, 17), status.NextChange);
    }),
    ("Before work hours waits for today's start", () =>
    {
        var status = WorkSchedule.Evaluate(Defaults(), On(2, 7));
        Assert.Equal(PresenceState.OffSchedule, status.State);
        Assert.Equal<DateTime?>(On(2, 8), status.NextChange);
    }),
    ("Friday evening skips the weekend", () =>
    {
        var status = WorkSchedule.Evaluate(Defaults(), On(6, 18));
        Assert.Equal(PresenceState.OffSchedule, status.State);
        Assert.Equal<DateTime?>(On(9, 8), status.NextChange);
    }),
    ("Saturday is off by default", () =>
    {
        var status = WorkSchedule.Evaluate(Defaults(), On(7, 12));
        Assert.Equal(PresenceState.OffSchedule, status.State);
        Assert.Equal<DateTime?>(On(9, 8), status.NextChange);
    }),
    ("Lunch break pauses and resumes", () =>
    {
        var settings = Defaults();
        settings.LunchBreakEnabled = true;
        var during = WorkSchedule.Evaluate(settings, On(2, 12, 10));
        Assert.Equal(PresenceState.Break, during.State);
        Assert.Equal<DateTime?>(On(2, 12, 30), during.NextChange);
        var before = WorkSchedule.Evaluate(settings, On(2, 11));
        Assert.Equal(PresenceState.Active, before.State);
        Assert.Equal<DateTime?>(On(2, 12), before.NextChange);
    }),
    ("A day off is skipped", () =>
    {
        var settings = Defaults();
        settings.DaysOff.Add(new DateOnly(2026, 11, 2));
        var status = WorkSchedule.Evaluate(settings, On(2, 10));
        Assert.Equal(PresenceState.DayOff, status.State);
        Assert.Equal<DateTime?>(On(3, 8), status.NextChange);
    }),
    ("Night shift runs past midnight", () =>
    {
        var settings = Defaults();
        foreach (var day in settings.Week)
            day.Enabled = day.Day == DayOfWeek.Monday;
        var monday = settings.GetDay(DayOfWeek.Monday)!;
        monday.Start = new TimeOnly(22, 0);
        monday.End = new TimeOnly(6, 0);

        var night = WorkSchedule.Evaluate(settings, On(3, 3));
        Assert.Equal(PresenceState.Active, night.State);
        Assert.Equal<DateTime?>(On(3, 6), night.NextChange);
        var morning = WorkSchedule.Evaluate(settings, On(3, 7));
        Assert.Equal(PresenceState.OffSchedule, morning.State);
        Assert.Equal<DateTime?>(On(9, 22), morning.NextChange);
    }),
    ("Equal start and end means a full day", () =>
    {
        var settings = Defaults();
        var monday = settings.GetDay(DayOfWeek.Monday)!;
        monday.Start = new TimeOnly(0, 0);
        monday.End = new TimeOnly(0, 0);
        var status = WorkSchedule.Evaluate(settings, On(2, 23, 30));
        Assert.Equal(PresenceState.Active, status.State);
        Assert.Equal<DateTime?>(On(3, 0), status.NextChange);
    }),
    ("Master switch off means disabled", () =>
    {
        var settings = Defaults();
        settings.IsEnabled = false;
        Assert.Equal(PresenceState.Disabled, PresencePolicy.Evaluate(settings, At(On(2, 10)), null).State);
    }),
    ("A boost beats the switch and the schedule", () =>
    {
        var settings = Defaults();
        settings.IsEnabled = false;
        var decision = PresencePolicy.Evaluate(settings, At(On(7, 12)), On(7, 13));
        Assert.Equal(PresenceState.Active, decision.State);
        Assert.True(decision.IsBoosted, "expected a boosted decision");
        Assert.Equal<DateTime?>(On(7, 13), decision.NextChange);
    }),
    ("An expired boost no longer counts", () =>
    {
        var decision = PresencePolicy.Evaluate(Defaults(), At(On(7, 12)), On(7, 11));
        Assert.Equal(PresenceState.OffSchedule, decision.State);
        Assert.True(!decision.IsBoosted, "expected no boost");
    }),
    ("Locking the PC pauses, even when boosted", () =>
    {
        var decision = PresencePolicy.Evaluate(Defaults(), At(On(2, 10), locked: true), On(2, 11));
        Assert.Equal(PresenceState.Locked, decision.State);
    }),
    ("Low battery pauses only when unplugged", () =>
    {
        Assert.Equal(PresenceState.LowBattery, PresencePolicy.Evaluate(Defaults(), At(On(2, 10), onBattery: true, battery: 10), null).State);
        Assert.Equal(PresenceState.Active, PresencePolicy.Evaluate(Defaults(), At(On(2, 10), onBattery: false, battery: 10), null).State);
        Assert.Equal(PresenceState.Active, PresencePolicy.Evaluate(Defaults(), At(On(2, 10), onBattery: true, battery: -1), null).State);
    }),
    ("Pause on battery power", () =>
    {
        var settings = Defaults();
        settings.PauseOnBattery = true;
        Assert.Equal(PresenceState.OnBattery, PresencePolicy.Evaluate(settings, At(On(2, 10), onBattery: true, battery: 80), null).State);
    }),
    ("Waits for watched apps", () =>
    {
        var settings = Defaults();
        settings.OnlyWhenAppsRunning = true;
        Assert.Equal(PresenceState.WaitingForApp, PresencePolicy.Evaluate(settings, At(On(2, 10), appRunning: false), null).State);
        Assert.Equal(PresenceState.Active, PresencePolicy.Evaluate(settings, At(On(2, 10), appRunning: true), null).State);
    }),
    ("Schedule off runs around the clock", () =>
    {
        var settings = Defaults();
        settings.UseSchedule = false;
        var decision = PresencePolicy.Evaluate(settings, At(On(7, 3)), null);
        Assert.Equal(PresenceState.Active, decision.State);
        Assert.Equal<DateTime?>(null, decision.NextChange);
    }),
    ("End of workday", () =>
    {
        Assert.Equal(On(2, 17), WorkSchedule.EndOfWorkday(Defaults(), On(2, 10)));
        Assert.Equal(On(2, 17), WorkSchedule.EndOfWorkday(Defaults(), On(2, 7)));
        Assert.Equal(On(8, 0), WorkSchedule.EndOfWorkday(Defaults(), On(7, 12)));
    }),
    ("Settings survive a save and load", () =>
    {
        var folder = Path.Combine(Path.GetTempPath(), "KeepGreen.Tests", Guid.NewGuid().ToString("N"));
        try
        {
            var store = new SettingsStore(folder);
            var settings = Defaults();
            settings.Style = NudgeStyle.PhantomKey;
            settings.IntervalSeconds = 90;
            settings.LunchStart = new TimeOnly(13, 15);
            settings.DaysOff.Add(new DateOnly(2026, 12, 24));
            settings.GetDay(DayOfWeek.Saturday)!.Enabled = true;
            settings.RemoteEnabled = true;
            settings.RemotePort = 50000;
            settings.RemoteKey = TestKey;
            store.SaveSettings(settings);

            var loaded = store.LoadSettings(new DateOnly(2026, 11, 1));
            Assert.Equal(NudgeStyle.PhantomKey, loaded.Style);
            Assert.Equal(90, loaded.IntervalSeconds);
            Assert.Equal(new TimeOnly(13, 15), loaded.LunchStart);
            Assert.Equal(new DateOnly(2026, 12, 24), loaded.DaysOff.Single());
            Assert.True(loaded.GetDay(DayOfWeek.Saturday)!.Enabled, "Saturday should stay enabled");
            Assert.True(loaded.RemoteEnabled, "the phone remote should stay on");
            Assert.Equal(50000, loaded.RemotePort);
            Assert.Equal(TestKey, loaded.RemoteKey);
        }
        finally
        {
            if (Directory.Exists(folder))
                Directory.Delete(folder, recursive: true);
        }
    }),
    ("A corrupt settings file falls back to defaults", () =>
    {
        var folder = Path.Combine(Path.GetTempPath(), "KeepGreen.Tests", Guid.NewGuid().ToString("N"));
        try
        {
            Directory.CreateDirectory(folder);
            var store = new SettingsStore(folder);
            File.WriteAllText(store.SettingsPath, "{ not json");
            var loaded = store.LoadSettings(new DateOnly(2026, 11, 1));
            Assert.Equal(60, loaded.IntervalSeconds);
            Assert.True(File.Exists(store.SettingsPath + ".broken"), "the broken file should be kept");
        }
        finally
        {
            if (Directory.Exists(folder))
                Directory.Delete(folder, recursive: true);
        }
    }),
    ("Normalize repairs bad values", () =>
    {
        var settings = new AppSettings { IntervalSeconds = 5, LowBatteryPercent = 200 };
        settings.Week.RemoveAt(3);
        settings.GetDay(DayOfWeek.Monday)!.Start = new TimeOnly(8, 10);
        settings.DaysOff.Add(new DateOnly(2026, 10, 1));
        settings.Normalize(new DateOnly(2026, 11, 1));
        Assert.Equal(AppSettings.MinIntervalSeconds, settings.IntervalSeconds);
        Assert.Equal(95, settings.LowBatteryPercent);
        Assert.Equal(7, settings.Week.Count);
        Assert.Equal(new TimeOnly(8, 0), settings.GetDay(DayOfWeek.Monday)!.Start);
        Assert.Equal(0, settings.DaysOff.Count);

        settings.IntervalSeconds = 999;
        settings.Normalize(new DateOnly(2026, 11, 1));
        Assert.Equal(AppSettings.MaxIntervalSeconds, settings.IntervalSeconds);
    }),
    ("Watched app names are cleaned up", () =>
    {
        var settings = new AppSettings { WatchedApps = "ms-teams.exe, Slack;  zoom slack" };
        Assert.Equal("ms-teams|Slack|zoom", string.Join("|", settings.WatchedAppNames()));
    }),
    ("Friendly times", () =>
    {
        var now = On(2, 9);
        Assert.True(Humanize.When(On(2, 17), now).StartsWith("today at", StringComparison.Ordinal), "today");
        Assert.True(Humanize.When(On(3, 8), now).StartsWith("tomorrow at", StringComparison.Ordinal), "tomorrow");
        Assert.True(Humanize.When(On(5, 8), now).StartsWith("Thursday at", StringComparison.Ordinal), "weekday");
        Assert.True(Humanize.When(On(20, 8), now).StartsWith("on 20 Nov at", StringComparison.Ordinal), "date");
    }),
    ("Friendly durations", () =>
    {
        Assert.Equal("42 s", Humanize.Duration(TimeSpan.FromSeconds(42)));
        Assert.Equal("5 min", Humanize.Duration(TimeSpan.FromMinutes(5.5)));
        Assert.Equal("6 h 12 min", Humanize.Duration(new TimeSpan(6, 12, 30)));
        Assert.Equal("2 h", Humanize.Duration(TimeSpan.FromHours(2)));
    }),
    ("Remote settings are off by default and repaired on load", () =>
    {
        var settings = new AppSettings();
        Assert.True(!settings.RemoteEnabled, "the phone remote should start off");
        Assert.Equal(47321, settings.RemotePort);
        Assert.Equal("", settings.RemoteKey);

        settings.RemotePort = 80;
        settings.RemoteKey = "not a key";
        settings.Normalize(new DateOnly(2026, 11, 1));
        Assert.Equal(1024, settings.RemotePort);
        Assert.Equal("", settings.RemoteKey);

        settings.RemotePort = 70000;
        settings.RemoteKey = TestKey;
        settings.Normalize(new DateOnly(2026, 11, 1));
        Assert.Equal(65535, settings.RemotePort);
        Assert.Equal(TestKey, settings.RemoteKey);
    }),
    ("Remote keys are 32 lowercase hex characters", () =>
    {
        var key = RemoteSignature.NewKey();
        Assert.True(RemoteSignature.IsValidKey(key), $"not a valid key: {key}");
        Assert.True(key != RemoteSignature.NewKey(), "two keys should differ");
        Assert.True(!RemoteSignature.IsValidKey(TestKey.ToUpperInvariant()), "upper case is not a key");
        Assert.True(!RemoteSignature.IsValidKey(TestKey[..31]), "31 characters is not a key");
    }),
    ("Remote signature matches the spec's test vector", () =>
    {
        Assert.Equal("GET\n/v1/status\n1700000000\n", RemoteSignature.Message("GET", "/v1/status", "1700000000", ""));
        Assert.Equal(
            "e61ba19958971173e1d8eb4038ff25f241eb73396f25529d28cfd3d602fd5e80",
            RemoteSignature.Compute(TestKey, "GET", "/v1/status", "1700000000", ""));
    }),
    ("Remote signatures need the right key, body and clock", () =>
    {
        const string body = "{\"enabled\":true}";
        var at = DateTimeOffset.FromUnixTimeSeconds(1700000000);
        var signature = RemoteSignature.Compute(TestKey, "POST", "/v1/enabled", "1700000000", body);
        SignatureCheck Check(string time, string? sig, string sentBody = body, string key = TestKey, long offset = 0) =>
            RemoteSignature.Verify(key, "POST", "/v1/enabled", time, sentBody, sig, at.AddSeconds(offset));

        Assert.Equal(SignatureCheck.Valid, Check("1700000000", signature));
        Assert.Equal(SignatureCheck.Valid, Check("1700000000", signature.ToUpperInvariant()));
        Assert.Equal(SignatureCheck.Valid, Check("1700000000", signature, offset: 120));
        Assert.Equal(SignatureCheck.Valid, Check("1700000000", signature, offset: -120));
        Assert.Equal(SignatureCheck.ClockSkew, Check("1700000000", signature, offset: 121));
        Assert.Equal(SignatureCheck.ClockSkew, Check("1700000000", signature, offset: -121));
        Assert.Equal(SignatureCheck.BadSignature, Check("1700000000", signature, sentBody: "{\"enabled\":false}"));
        Assert.Equal(SignatureCheck.BadSignature, Check("1700000001", signature));
        Assert.Equal(SignatureCheck.BadSignature, Check("1700000000", signature, key: RemoteSignature.NewKey()));
        Assert.Equal(SignatureCheck.BadSignature, Check("1700000000", RemoteSignature.Compute("", "POST", "/v1/enabled", "1700000000", body), key: ""));
        Assert.Equal(SignatureCheck.Missing, Check("1700000000", null));
        Assert.Equal(SignatureCheck.Missing, Check("", signature));
        Assert.Equal(SignatureCheck.Missing, Check("-1700000000", signature));
        Assert.Equal(SignatureCheck.Missing, Check("1700000000", "abc"));
    }),
    ("A pairing code has 6 digits and lasts 10 minutes", () =>
    {
        var clock = new ManualClock(new DateTimeOffset(2026, 11, 2, 9, 0, 0, TimeSpan.Zero));
        var pairing = new PairingCodes(clock);
        var first = pairing.Current;
        Assert.True(first.Code.Length == 6 && first.Code.All(char.IsAsciiDigit), $"not 6 digits: {first.Code}");
        Assert.Equal(clock.Now.AddMinutes(10), first.ExpiresAt);

        clock.Now = clock.Now.AddMinutes(9).AddSeconds(59);
        Assert.Equal(first, pairing.Current);

        clock.Now = first.ExpiresAt;
        var second = pairing.Current;
        Assert.True(second.Code != first.Code, "an expired code should be replaced");
        Assert.Equal(PairingResult.WrongCode, pairing.TryPair(first.Code));

        pairing.Renew();
        Assert.True(pairing.Current.Code != second.Code, "New code should replace the code");
    }),
    ("A pairing code works once", () =>
    {
        var pairing = new PairingCodes(new ManualClock(new DateTimeOffset(2026, 11, 2, 9, 0, 0, TimeSpan.Zero)));
        var code = pairing.Current.Code;
        Assert.Equal(PairingResult.Paired, pairing.TryPair($" {code[..3]} {code[3..]} "));
        Assert.True(pairing.Current.Code != code, "the code should be replaced after pairing");
        Assert.Equal(PairingResult.WrongCode, pairing.TryPair(code));
    }),
    ("Five wrong pairing codes close pairing for a minute", () =>
    {
        var clock = new ManualClock(new DateTimeOffset(2026, 11, 2, 9, 0, 0, TimeSpan.Zero));
        var pairing = new PairingCodes(clock);
        var code = pairing.Current.Code;
        for (var attempt = 1; attempt <= PairingCodes.MaxWrongAttempts; attempt++)
            Assert.Equal(PairingResult.WrongCode, pairing.TryPair(WrongCode(code)));

        var replaced = pairing.Current.Code;
        Assert.True(replaced != code, "the code should be replaced after 5 wrong tries");
        Assert.Equal<DateTimeOffset?>(clock.Now.AddSeconds(60), pairing.LockedUntil);
        Assert.Equal(PairingResult.LockedOut, pairing.TryPair(replaced));

        clock.Now = clock.Now.AddSeconds(59);
        Assert.Equal(PairingResult.LockedOut, pairing.TryPair(replaced));

        clock.Now = clock.Now.AddSeconds(1);
        Assert.Equal<DateTimeOffset?>(null, pairing.LockedUntil);
        Assert.Equal(PairingResult.Paired, pairing.TryPair(replaced));
    }),
    ("Remote status JSON matches the spec", () =>
    {
        var status = new RemoteStatus
        {
            Name = "DESKTOP-ABC",
            Platform = "windows",
            Version = "2.0.0",
            State = PresenceState.OffSchedule,
            IsEnabled = true,
            IsBoosted = true,
            BoostUntil = new DateTimeOffset(2026, 11, 5, 14, 30, 0, 250, TimeSpan.FromHours(4)),
            Headline = "Outside your work hours",
            Detail = "Turns on by itself tomorrow at 08:00.",
            IdleSeconds = 12,
            NudgesToday = 87,
            GreenSecondsToday = 22320,
        };

        using var json = JsonDocument.Parse(RemoteJson.Serialize(status));
        var root = json.RootElement;
        Assert.Equal(
            "name,platform,version,state,isActive,isEnabled,isBoosted,boostUntil,headline,detail,idleSeconds,nudgesToday,greenSecondsToday",
            string.Join(",", root.EnumerateObject().Select(property => property.Name)));
        Assert.Equal("OffSchedule", root.GetProperty("state").GetString());
        Assert.Equal(JsonValueKind.False, root.GetProperty("isActive").ValueKind);
        Assert.Equal("2026-11-05T14:30:00+04:00", root.GetProperty("boostUntil").GetString());
        Assert.Equal(22320, root.GetProperty("greenSecondsToday").GetInt32());

        using var noBoost = JsonDocument.Parse(RemoteJson.Serialize(status with { BoostUntil = null }));
        Assert.Equal(JsonValueKind.Null, noBoost.RootElement.GetProperty("boostUntil").ValueKind);
    }),
    ("Remote server: ping and pairing", () => WithServer(async (server, client, handler, pairing) =>
    {
        var paired = new List<string>();
        server.Paired += (_, device) => paired.Add(device);

        var (status, ping) = await SendAsync(client, Unsigned(HttpMethod.Get, "/v1/ping"));
        Assert.Equal(200, status);
        Assert.Equal("app,api,name,platform,version", string.Join(",", ping.EnumerateObject().Select(property => property.Name)));
        Assert.Equal("KeepGreen", ping.GetProperty("app").GetString());
        Assert.Equal(1, ping.GetProperty("api").GetInt32());
        Assert.Equal("TEST-PC", ping.GetProperty("name").GetString());

        var code = pairing.Current.Code;
        (status, var error) = await SendAsync(client, Unsigned(HttpMethod.Post, "/v1/pair", $"{{\"code\": \"{WrongCode(code)}\", \"device\": \"Phone\"}}"));
        Assert.Equal(401, status);
        Assert.True(error.GetProperty("error").GetString()!.Length > 0, "expected an error message");

        (status, var pair) = await SendAsync(client, Unsigned(HttpMethod.Post, "/v1/pair", $"{{\"code\": \"{code}\", \"device\": \"Mahdhi's iPhone\"}}"));
        Assert.Equal(200, status);
        Assert.Equal("key,name,platform,version", string.Join(",", pair.EnumerateObject().Select(property => property.Name)));
        Assert.Equal(TestKey, pair.GetProperty("key").GetString());
        Assert.Equal("windows", pair.GetProperty("platform").GetString());
        Assert.Equal("Mahdhi's iPhone", paired.Single());
        Assert.True(pairing.Current.Code != code, "the code should be replaced after pairing");

        code = pairing.Current.Code;
        for (var attempt = 1; attempt <= PairingCodes.MaxWrongAttempts; attempt++)
        {
            (status, _) = await SendAsync(client, Unsigned(HttpMethod.Post, "/v1/pair", $"{{\"code\": \"{WrongCode(code)}\"}}"));
            Assert.Equal(401, status);
        }

        using var locked = await client.PostAsync("/v1/pair", new StringContent($"{{\"code\": \"{pairing.Current.Code}\"}}"));
        Assert.Equal(429, (int)locked.StatusCode);
        Assert.True(locked.Headers.RetryAfter?.Delta is { TotalSeconds: > 0 and <= 60 }, "expected a Retry-After header");

        (status, _) = await SendAsync(client, Unsigned(HttpMethod.Post, "/v1/pair", "{}"));
        Assert.Equal(400, status);
    })),
    ("Remote server: signed requests", () => WithServer(async (server, client, handler, pairing) =>
    {
        var (status, json) = await SendAsync(client, Signed(HttpMethod.Get, "/v1/status"));
        Assert.Equal(200, status);
        Assert.Equal("TEST-PC", json.GetProperty("name").GetString());
        Assert.Equal("Active", json.GetProperty("state").GetString());
        Assert.Equal(JsonValueKind.Null, json.GetProperty("boostUntil").ValueKind);

        (status, _) = await SendAsync(client, Signed(HttpMethod.Get, "/v1/status?refresh=1"));
        Assert.Equal(200, status);

        (status, json) = await SendAsync(client, Unsigned(HttpMethod.Get, "/v1/status"));
        Assert.Equal(401, status);
        Assert.True(json.GetProperty("error").GetString()!.Length > 0, "expected an error message");

        (status, _) = await SendAsync(client, Signed(HttpMethod.Get, "/v1/status", key: RemoteSignature.NewKey()));
        Assert.Equal(401, status);

        (status, _) = await SendAsync(client, Signed(HttpMethod.Get, "/v1/status", time: DateTimeOffset.UtcNow.ToUnixTimeSeconds() - 300));
        Assert.Equal(401, status);

        // "Unpair all phones": the old key stops working right away.
        server.Key = RemoteSignature.NewKey();
        (status, _) = await SendAsync(client, Signed(HttpMethod.Get, "/v1/status"));
        Assert.Equal(401, status);
        (status, _) = await SendAsync(client, Signed(HttpMethod.Get, "/v1/status", key: server.Key));
        Assert.Equal(200, status);
    })),
    ("Remote server: commands", () => WithServer(async (server, client, handler, pairing) =>
    {
        var (status, json) = await SendAsync(client, Signed(HttpMethod.Post, "/v1/enabled", "{\"enabled\": false}"));
        Assert.Equal(200, status);
        Assert.True(!handler.Enabled, "the switch should be off");
        Assert.Equal("Disabled", json.GetProperty("state").GetString());
        Assert.Equal(JsonValueKind.False, json.GetProperty("isEnabled").ValueKind);

        (status, json) = await SendAsync(client, Signed(HttpMethod.Post, "/v1/boost", "{\"minutes\": 60}"));
        Assert.Equal(200, status);
        Assert.Equal<int?>(60, handler.BoostMinutes);
        Assert.Equal(JsonValueKind.True, json.GetProperty("isBoosted").ValueKind);

        (status, _) = await SendAsync(client, Signed(HttpMethod.Post, "/v1/boost", "{\"untilEndOfWorkday\": true}"));
        Assert.Equal(200, status);
        Assert.True(handler.BoostedUntilEndOfWorkday, "expected a boost until the end of the workday");

        (status, _) = await SendAsync(client, Signed(HttpMethod.Post, "/v1/boost", "{\"minutes\": 0}"));
        Assert.Equal(400, status);
        (status, _) = await SendAsync(client, Signed(HttpMethod.Post, "/v1/boost", "{\"minutes\": 721}"));
        Assert.Equal(400, status);

        (status, _) = await SendAsync(client, Signed(HttpMethod.Post, "/v1/boost/cancel", "{}"));
        Assert.Equal(200, status);
        Assert.True(handler.BoostCancelled, "the boost should be cancelled");

        (status, _) = await SendAsync(client, Signed(HttpMethod.Post, "/v1/enabled", "{ not json"));
        Assert.Equal(400, status);
        (status, _) = await SendAsync(client, Signed(HttpMethod.Post, "/v1/enabled", "{}"));
        Assert.Equal(400, status);
    })),
    ("Remote server: bad requests", () => WithServer(async (server, client, handler, pairing) =>
    {
        var oversize = $"{{\"enabled\": true, \"pad\": \"{new string('x', 5000)}\"}}";
        var (status, json) = await SendAsync(client, Signed(HttpMethod.Post, "/v1/enabled", oversize));
        Assert.Equal(400, status);
        Assert.True(json.GetProperty("error").GetString()!.Contains("4 KB", StringComparison.Ordinal), "expected the size limit in the error");

        (status, _) = await SendAsync(client, Signed(HttpMethod.Get, "/v1/nothing-here"));
        Assert.Equal(404, status);

        using (var wrongMethod = await client.GetAsync("/v1/enabled"))
        {
            Assert.Equal(405, (int)wrongMethod.StatusCode);
            Assert.Equal("POST", string.Join(",", wrongMethod.Content.Headers.Allow));
        }

        var raw = await SendRawAsync(server.Port, "HELLO\r\n\r\n");
        Assert.True(raw.StartsWith("HTTP/1.1 400 ", StringComparison.Ordinal), $"expected a 400, got: {raw}");
        Assert.True(raw.Contains("Connection: close", StringComparison.Ordinal), "expected Connection: close");

        // Still answering after all that.
        (status, _) = await SendAsync(client, Unsigned(HttpMethod.Get, "/v1/ping"));
        Assert.Equal(200, status);
    })),
    ("Remote server drops a silent client without blocking others", () =>
    {
        using var server = new RemoteServer(new FakeRemoteHandler(), new PairingCodes())
        {
            Key = TestKey,
            RequestTimeout = TimeSpan.FromMilliseconds(300),
        };
        Assert.True(server.Start(0, IPAddress.Loopback), server.Error ?? "the server should start");
        Run(async () =>
        {
            using var silent = new TcpClient();
            await silent.ConnectAsync(IPAddress.Loopback, server.Port);

            using var client = NewClient(server.Port);
            var (status, _) = await SendAsync(client, Unsigned(HttpMethod.Get, "/v1/ping"));
            Assert.Equal(200, status);

            using var wait = new CancellationTokenSource(TimeSpan.FromSeconds(5));
            try
            {
                Assert.Equal(0, await silent.GetStream().ReadAsync(new byte[16], wait.Token));
            }
            catch (IOException)
            {
                // A reset also means the server hung up.
            }
        });
    }),
    ("Remote server reports a busy port and restarts", () =>
    {
        using var first = new RemoteServer(new FakeRemoteHandler(), new PairingCodes()) { Key = TestKey };
        using var second = new RemoteServer(new FakeRemoteHandler(), new PairingCodes()) { Key = TestKey };
        Assert.True(first.Start(0, IPAddress.Loopback), first.Error ?? "the first server should start");
        var port = first.Port;

        Assert.True(!second.Start(port, IPAddress.Loopback), "the port should be busy");
        Assert.Equal(RemoteServerState.Failed, second.State);
        Assert.True(second.Error!.Contains("already used", StringComparison.Ordinal), $"unexpected error: {second.Error}");

        first.Stop();
        Assert.Equal(RemoteServerState.Stopped, first.State);
        Assert.Equal(0, first.Port);
        Assert.True(second.Start(port, IPAddress.Loopback), second.Error ?? "the port should be free again");
        Assert.Equal(port, second.Port);
    }),
};

var failed = 0;
foreach (var (name, run) in tests)
{
    try
    {
        run();
        Console.WriteLine($"  PASS  {name}");
    }
    catch (Exception ex)
    {
        failed++;
        Console.WriteLine($"  FAIL  {name}: {ex.Message}");
    }
}

Console.WriteLine();
Console.WriteLine($"{tests.Length - failed}/{tests.Length} tests passed");
return failed == 0 ? 0 : 1;

internal static class Assert
{
    public static void Equal<T>(T expected, T actual)
    {
        if (!EqualityComparer<T>.Default.Equals(expected, actual))
            throw new InvalidOperationException($"expected <{expected}> but got <{actual}>");
    }

    public static void True(bool condition, string message)
    {
        if (!condition)
            throw new InvalidOperationException(message);
    }
}

/// <summary>A clock the pairing tests move by hand.</summary>
internal sealed class ManualClock(DateTimeOffset start) : TimeProvider
{
    public DateTimeOffset Now { get; set; } = start;

    public override DateTimeOffset GetUtcNow() => Now;
}

/// <summary>Stands in for the app and remembers what the phone asked for.</summary>
internal sealed class FakeRemoteHandler : IRemoteHandler
{
    public RemoteIdentity Identity { get; } = new("TEST-PC", "windows", "9.9.9");

    public bool Enabled { get; private set; } = true;

    public int? BoostMinutes { get; private set; }

    public bool BoostedUntilEndOfWorkday { get; private set; }

    public bool BoostCancelled { get; private set; }

    public Task<RemoteStatus> GetStatusAsync(CancellationToken cancellationToken) => Task.FromResult(new RemoteStatus
    {
        Name = Identity.Name,
        Platform = Identity.Platform,
        Version = Identity.Version,
        State = Enabled ? PresenceState.Active : PresenceState.Disabled,
        IsActive = Enabled,
        IsEnabled = Enabled,
        IsBoosted = BoostMinutes is not null && !BoostCancelled,
        Headline = Enabled ? "You're staying green" : "KeepGreen is off",
    });

    public Task SetEnabledAsync(bool enabled, CancellationToken cancellationToken)
    {
        Enabled = enabled;
        return Task.CompletedTask;
    }

    public Task BoostAsync(int minutes, CancellationToken cancellationToken)
    {
        BoostMinutes = minutes;
        return Task.CompletedTask;
    }

    public Task BoostUntilEndOfWorkdayAsync(CancellationToken cancellationToken)
    {
        BoostedUntilEndOfWorkday = true;
        return Task.CompletedTask;
    }

    public Task CancelBoostAsync(CancellationToken cancellationToken)
    {
        BoostCancelled = true;
        return Task.CompletedTask;
    }
}
