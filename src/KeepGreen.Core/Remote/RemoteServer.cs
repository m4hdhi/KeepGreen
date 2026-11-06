using System.Globalization;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Text.Json;

namespace KeepGreen.Core.Remote;

public enum RemoteServerState
{
    Stopped,
    Listening,

    /// <summary>The port couldn't be opened, or the listener broke. <see cref="RemoteServer.Error"/> says why.</summary>
    Failed,
}

/// <summary>
/// The phone remote: a tiny HTTP/1.1 server for the API in docs/remote-api.md. One request per
/// connection, JSON in and out. Built on <see cref="TcpListener"/> because HttpListener needs
/// admin rights to listen beyond localhost.
/// </summary>
public sealed class RemoteServer : IDisposable
{
    public const int DefaultPort = 47321;
    public const int MaxBodyBytes = 4 * 1024;
    public const int MinBoostMinutes = 1;
    public const int MaxBoostMinutes = 720;

    private const int MaxHeaderBytes = 8 * 1024;
    private const int MaxConnections = 32;

    private static readonly Dictionary<string, string> Routes = new(StringComparer.Ordinal)
    {
        ["/v1/ping"] = "GET",
        ["/v1/pair"] = "POST",
        ["/v1/status"] = "GET",
        ["/v1/enabled"] = "POST",
        ["/v1/boost"] = "POST",
        ["/v1/boost/cancel"] = "POST",
    };

    private static readonly UTF8Encoding StrictUtf8 = new(encoderShouldEmitUTF8Identifier: false, throwOnInvalidBytes: true);

    private readonly IRemoteHandler _handler;
    private readonly PairingCodes _pairing;
    private readonly TimeProvider _time;
    private readonly Lock _gate = new();
    private TcpListener? _listener;
    private CancellationTokenSource? _stopping;
    private volatile string _key = "";
    private int _connections;
    private bool _disposed;

    public RemoteServer(IRemoteHandler handler, PairingCodes pairing, TimeProvider? time = null)
    {
        _handler = handler;
        _pairing = pairing;
        _time = time ?? TimeProvider.System;
    }

    /// <summary>Raised after <see cref="State"/> changes, sometimes on a server thread.</summary>
    public event EventHandler? StateChanged;

    /// <summary>Raised on a server thread with the phone's name, after it pairs.</summary>
    public event EventHandler<string>? Paired;

    /// <summary>The shared key handed out when pairing and used to check signatures. Can change while running.</summary>
    public string Key
    {
        get => _key;
        set => _key = value ?? "";
    }

    /// <summary>How long a client gets to send its request, and the app gets to answer it.</summary>
    public TimeSpan RequestTimeout { get; init; } = TimeSpan.FromSeconds(10);

    public RemoteServerState State { get; private set; }

    /// <summary>The port in use while listening, otherwise 0.</summary>
    public int Port { get; private set; }

    /// <summary>A friendly reason when <see cref="State"/> is Failed.</summary>
    public string? Error { get; private set; }

    /// <summary>Starts listening, or restarts on a new port. Port 0 picks any free port.</summary>
    /// <param name="address">Where to listen; all IPv4 interfaces by default.</param>
    /// <returns>False if the port couldn't be opened; <see cref="Error"/> says why.</returns>
    public bool Start(int port, IPAddress? address = null)
    {
        bool started;
        lock (_gate)
        {
            ObjectDisposedException.ThrowIf(_disposed, this);
            StopListening();

            var listener = new TcpListener(address ?? IPAddress.Any, port);
            try
            {
                listener.Start();
                _listener = listener;
                _stopping = new CancellationTokenSource();
                var token = _stopping.Token;
                _ = Task.Run(() => AcceptLoopAsync(listener, token));
                SetState(RemoteServerState.Listening, ((IPEndPoint)listener.LocalEndpoint).Port, null);
                started = true;
            }
            catch (SocketException ex)
            {
                listener.Stop();
                SetState(RemoteServerState.Failed, 0, Describe(ex, port));
                started = false;
            }
        }

        StateChanged?.Invoke(this, EventArgs.Empty);
        return started;
    }

    public void Stop()
    {
        lock (_gate)
        {
            if (_disposed || (_listener is null && State == RemoteServerState.Stopped))
                return;
            StopListening();
            SetState(RemoteServerState.Stopped, 0, null);
        }

        StateChanged?.Invoke(this, EventArgs.Empty);
    }

    public void Dispose()
    {
        lock (_gate)
        {
            if (_disposed)
                return;
            _disposed = true;
            StopListening();
            SetState(RemoteServerState.Stopped, 0, null);
        }
    }

    private void SetState(RemoteServerState state, int port, string? error)
    {
        State = state;
        Port = port;
        Error = error;
    }

    /// <summary>Closes the listener and cancels open connections. Doesn't wait for them, so it never blocks the caller.</summary>
    private void StopListening()
    {
        _stopping?.Cancel();
        _stopping = null;
        _listener?.Stop();
        _listener = null;
    }

    private static string Describe(SocketException ex, int port) => ex.SocketErrorCode switch
    {
        SocketError.AddressAlreadyInUse => $"Port {port} is already used by another app.",
        SocketError.AccessDenied => $"This PC doesn't allow apps to use port {port}.",
        _ => $"Couldn't open port {port}. {ex.Message}",
    };

    private async Task AcceptLoopAsync(TcpListener listener, CancellationToken token)
    {
        while (!token.IsCancellationRequested)
        {
            Socket socket;
            try
            {
                socket = await listener.AcceptSocketAsync(token);
            }
            catch (Exception) when (token.IsCancellationRequested)
            {
                return;
            }
            catch (SocketException)
            {
                // Usually a client that hung up before we picked it up. Pause briefly in case it isn't.
                await Task.Delay(100, CancellationToken.None);
                continue;
            }
            catch (Exception ex)
            {
                lock (_gate)
                {
                    if (token.IsCancellationRequested)
                        return;
                    StopListening();
                    SetState(RemoteServerState.Failed, 0, $"The phone remote stopped. {ex.Message}");
                }

                StateChanged?.Invoke(this, EventArgs.Empty);
                return;
            }

            if (Interlocked.Increment(ref _connections) > MaxConnections)
            {
                Interlocked.Decrement(ref _connections);
                socket.Dispose();
                continue;
            }

            _ = ServeAsync(socket, token);
        }
    }

    private async Task ServeAsync(Socket socket, CancellationToken stopping)
    {
        try
        {
            using var deadline = CancellationTokenSource.CreateLinkedTokenSource(stopping);
            deadline.CancelAfter(RequestTimeout);
            using var stream = new NetworkStream(socket, ownsSocket: true);

            Response response;
            try
            {
                var request = await ReadRequestAsync(stream, deadline.Token);

                // A fresh deadline for the app to answer, however long the client took.
                deadline.CancelAfter(RequestTimeout);
                response = await RouteAsync(request, deadline.Token);
            }
            catch (BadRequestException ex)
            {
                response = Response.Error(400, ex.Message);
            }

            await stream.WriteAsync(response.ToBytes(), deadline.Token);
            await CloseGracefullyAsync(socket, stream);
        }
        catch (Exception)
        {
            // Timeouts, hang-ups and broken clients all end here: one bad connection never stops the server.
        }
        finally
        {
            socket.Dispose();
            Interlocked.Decrement(ref _connections);
        }
    }

    /// <summary>
    /// Says we're done, then reads and drops whatever the client still sends (say, the rest of an
    /// oversize body) until it hangs up. Closing with unread data makes Windows reset the connection,
    /// and the client could lose our answer.
    /// </summary>
    private static async Task CloseGracefullyAsync(Socket socket, NetworkStream stream)
    {
        socket.Shutdown(SocketShutdown.Send);
        using var linger = new CancellationTokenSource(TimeSpan.FromSeconds(2));
        var scratch = new byte[1024];
        var drained = 0;
        while (drained < 64 * 1024)
        {
            var read = await stream.ReadAsync(scratch, linger.Token);
            if (read == 0)
                return;
            drained += read;
        }
    }

    private static async Task<Request> ReadRequestAsync(NetworkStream stream, CancellationToken token)
    {
        var buffer = new byte[MaxHeaderBytes + MaxBodyBytes];
        var filled = 0;
        var headerEnd = -1;
        while (headerEnd < 0)
        {
            if (filled == MaxHeaderBytes)
                throw new BadRequestException("The request headers are too large.");

            var read = await stream.ReadAsync(buffer.AsMemory(filled, MaxHeaderBytes - filled), token);
            if (read == 0)
                throw new EndOfStreamException();

            // The blank line may straddle two reads, so look a few bytes back.
            var searchFrom = Math.Max(0, filled - 3);
            filled += read;
            var found = buffer.AsSpan(searchFrom, filled - searchFrom).IndexOf("\r\n\r\n"u8);
            if (found >= 0)
                headerEnd = searchFrom + found;
        }

        var lines = Encoding.Latin1.GetString(buffer, 0, headerEnd).Split("\r\n");
        var requestLine = lines[0].Split(' ');
        if (requestLine.Length != 3 || !requestLine[1].StartsWith('/') ||
            !requestLine[2].StartsWith("HTTP/1.", StringComparison.Ordinal))
        {
            throw new BadRequestException("That isn't an HTTP request KeepGreen understands.");
        }

        var headers = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (var line in lines.Skip(1))
        {
            var colon = line.IndexOf(':');
            if (colon <= 0)
                throw new BadRequestException("A request header is malformed.");
            var name = line[..colon].Trim();
            var value = line[(colon + 1)..].Trim();
            if (headers.TryGetValue(name, out var earlier) && earlier != value &&
                name.Equals("Content-Length", StringComparison.OrdinalIgnoreCase))
            {
                throw new BadRequestException("The request has two different Content-Length headers.");
            }

            headers[name] = value;
        }

        if (headers.ContainsKey("Transfer-Encoding"))
            throw new BadRequestException("Send the body with a Content-Length header instead of chunks.");

        long length = 0;
        if (headers.TryGetValue("Content-Length", out var declared) &&
            !long.TryParse(declared, NumberStyles.None, CultureInfo.InvariantCulture, out length))
        {
            throw new BadRequestException("The Content-Length header isn't a number.");
        }

        if (length > MaxBodyBytes)
            throw new BadRequestException("The request body is larger than 4 KB.");

        var bodyStart = headerEnd + 4;
        var bodyEnd = bodyStart + (int)length;
        if (filled < bodyEnd && headers.TryGetValue("Expect", out var expect) &&
            expect.Equals("100-continue", StringComparison.OrdinalIgnoreCase))
        {
            await stream.WriteAsync("HTTP/1.1 100 Continue\r\n\r\n"u8.ToArray(), token);
        }

        while (filled < bodyEnd)
        {
            var read = await stream.ReadAsync(buffer.AsMemory(filled, bodyEnd - filled), token);
            if (read == 0)
                throw new EndOfStreamException();
            filled += read;
        }

        string body;
        try
        {
            body = StrictUtf8.GetString(buffer, bodyStart, (int)length);
        }
        catch (DecoderFallbackException)
        {
            throw new BadRequestException("The request body isn't valid UTF-8.");
        }

        // The path is signed without its query string.
        var path = requestLine[1].Split('?', 2)[0];
        return new Request(requestLine[0], path, headers, body);
    }

    private async Task<Response> RouteAsync(Request request, CancellationToken token)
    {
        if (!Routes.TryGetValue(request.Path, out var method))
            return Response.Error(404, "There's nothing at this address. Is KeepGreen on your PC up to date?");
        if (request.Method != method)
            return Response.Error(405, $"Use {method} for {request.Path}.") with { Allow = method };

        var identity = _handler.Identity;
        if (request.Path == "/v1/ping")
            return Response.Ok(new RemotePing("KeepGreen", 1, identity.Name, identity.Platform, identity.Version));
        if (request.Path == "/v1/pair")
            return Pair(request, identity);

        var check = RemoteSignature.Verify(
            Key,
            request.Method,
            request.Path,
            request.Headers.GetValueOrDefault(RemoteSignature.TimeHeader),
            request.Body,
            request.Headers.GetValueOrDefault(RemoteSignature.SignatureHeader),
            _time.GetUtcNow());
        switch (check)
        {
            case SignatureCheck.Missing:
                return Response.Error(401, "This request isn't signed. Pair your phone with this PC first.");
            case SignatureCheck.BadSignature:
                return Response.Error(401, "This phone isn't paired with this PC anymore. Pair it again.");
            case SignatureCheck.ClockSkew:
                return Response.Error(401, "The clocks on your phone and PC are more than 2 minutes apart. Check the time on both.");
        }

        try
        {
            switch (request.Path)
            {
                case "/v1/enabled":
                    var enabled = Parse<RemoteEnabledRequest>(request.Body)?.Enabled
                        ?? throw new BadRequestException("Send {\"enabled\": true} or {\"enabled\": false}.");
                    await _handler.SetEnabledAsync(enabled, token);
                    break;

                case "/v1/boost":
                    var boost = Parse<RemoteBoostRequest>(request.Body);
                    if (boost?.UntilEndOfWorkday == true)
                        await _handler.BoostUntilEndOfWorkdayAsync(token);
                    else if (boost?.Minutes is { } minutes and >= MinBoostMinutes and <= MaxBoostMinutes)
                        await _handler.BoostAsync(minutes, token);
                    else
                        throw new BadRequestException("Send {\"minutes\": 1 to 720} or {\"untilEndOfWorkday\": true}.");
                    break;

                case "/v1/boost/cancel":
                    await _handler.CancelBoostAsync(token);
                    break;
            }

            return Response.Ok(await _handler.GetStatusAsync(token));
        }
        catch (Exception ex) when (ex is not (BadRequestException or OperationCanceledException))
        {
            return Response.Error(500, "KeepGreen on your PC couldn't do that. Try again.");
        }
    }

    private Response Pair(Request request, RemoteIdentity identity)
    {
        var body = Parse<RemotePairRequest>(request.Body);
        if (string.IsNullOrWhiteSpace(body?.Code))
            throw new BadRequestException("Send the 6-digit code shown in KeepGreen on your PC.");

        var key = Key;
        if (!RemoteSignature.IsValidKey(key))
            return Response.Error(500, "The phone remote isn't ready yet. Try again in a moment.");

        switch (_pairing.TryPair(body.Code))
        {
            case PairingResult.LockedOut:
                var wait = (_pairing.LockedUntil ?? _time.GetUtcNow()) - _time.GetUtcNow();
                return Response.Error(429, "Too many wrong codes. Wait a minute, then try the new code on your PC.")
                    with { RetryAfterSeconds = Math.Max(1, (int)Math.Ceiling(wait.TotalSeconds)) };
            case PairingResult.WrongCode:
                return Response.Error(401, "That code is wrong or has expired. Check the code in KeepGreen on your PC.");
        }

        Paired?.Invoke(this, DeviceName(body.Device));
        return Response.Ok(new RemotePairResponse(key, identity.Name, identity.Platform, identity.Version));
    }

    private static T? Parse<T>(string body)
        where T : class
    {
        try
        {
            return RemoteJson.Deserialize<T>(body);
        }
        catch (JsonException)
        {
            throw new BadRequestException("The request body isn't valid JSON.");
        }
    }

    /// <summary>The phone's name, safe to show in a notification.</summary>
    private static string DeviceName(string? device)
    {
        var name = string.Concat((device ?? "").Where(c => !char.IsControl(c))).Trim();
        if (name.Length > 40)
            name = name[..(char.IsHighSurrogate(name[39]) ? 39 : 40)].TrimEnd();
        return name.Length == 0 ? "A phone" : name;
    }

    private sealed record Request(string Method, string Path, Dictionary<string, string> Headers, string Body);

    private sealed record Response(int Status, byte[] Body)
    {
        public string? Allow { get; init; }

        public int? RetryAfterSeconds { get; init; }

        public static Response Ok(object value) => new(200, RemoteJson.Serialize(value));

        public static Response Error(int status, string message) => new(status, RemoteJson.Serialize(new RemoteError(message)));

        public byte[] ToBytes()
        {
            var head = new StringBuilder()
                .Append(CultureInfo.InvariantCulture, $"HTTP/1.1 {Status} {ReasonPhrase(Status)}\r\n")
                .Append("Content-Type: application/json; charset=utf-8\r\n")
                .Append(CultureInfo.InvariantCulture, $"Content-Length: {Body.Length}\r\n")
                .Append("Cache-Control: no-store\r\n")
                .Append("Connection: close\r\n");
            if (Allow is not null)
                head.Append(CultureInfo.InvariantCulture, $"Allow: {Allow}\r\n");
            if (RetryAfterSeconds is { } seconds)
                head.Append(CultureInfo.InvariantCulture, $"Retry-After: {seconds}\r\n");
            head.Append("\r\n");

            // One buffer, so the answer usually leaves in a single packet.
            return [.. Encoding.ASCII.GetBytes(head.ToString()), .. Body];
        }

        private static string ReasonPhrase(int status) => status switch
        {
            200 => "OK",
            400 => "Bad Request",
            401 => "Unauthorized",
            404 => "Not Found",
            405 => "Method Not Allowed",
            429 => "Too Many Requests",
            _ => "Internal Server Error",
        };
    }

    private sealed class BadRequestException(string message) : Exception(message);
}
