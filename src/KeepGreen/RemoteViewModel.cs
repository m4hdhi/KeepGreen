using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Windows.Threading;
using KeepGreen.Core;
using KeepGreen.Core.Remote;

namespace KeepGreen;

/// <summary>One address a phone can reach this PC at, e.g. "192.168.1.20:47321" on "Wi-Fi".</summary>
internal sealed record RemoteAddress(string Address, string Network);

/// <summary>
/// The "Phone remote" part of the Settings page. While the remote is on it ticks once a second,
/// because the pairing code and its countdown change by themselves.
/// </summary>
internal sealed class RemoteViewModel : ObservableObject, IDisposable
{
    private const string UnpairIdle = "Makes a new key, so every paired phone is signed out.";

    private readonly AppSettings _settings;
    private readonly RemoteServer _server;
    private readonly PairingCodes _pairing;
    private readonly DispatcherTimer _timer = new() { Interval = TimeSpan.FromSeconds(1) };
    private IReadOnlyList<RemoteAddress> _addresses = [];
    private string _code = "";
    private string _codeHint = "";
    private string _statusText = "";
    private StatusTone _tone = StatusTone.Gray;
    private string _unpairHint = UnpairIdle;
    private bool _watchingNetwork;

    public RemoteViewModel(AppSettings settings, RemoteServer server, PairingCodes pairing)
    {
        _settings = settings;
        _server = server;
        _pairing = pairing;
        _timer.Tick += (_, _) => RefreshCode();
    }

    public IReadOnlyList<RemoteAddress> Addresses
    {
        get => _addresses;
        private set
        {
            if (SetProperty(ref _addresses, value))
                OnPropertyChanged(nameof(HasAddresses));
        }
    }

    public bool HasAddresses => _addresses.Count > 0;

    /// <summary>The pairing code as shown, e.g. "123 456".</summary>
    public string Code { get => _code; private set => SetProperty(ref _code, value); }

    /// <summary>How long the code stays valid, or how long pairing is closed after too many wrong codes.</summary>
    public string CodeHint { get => _codeHint; private set => SetProperty(ref _codeHint, value); }

    public string StatusText { get => _statusText; private set => SetProperty(ref _statusText, value); }

    public StatusTone Tone { get => _tone; private set => SetProperty(ref _tone, value); }

    public string UnpairHint { get => _unpairHint; private set => SetProperty(ref _unpairHint, value); }

    public void NewCode()
    {
        _pairing.Renew();
        RefreshCode();
    }

    /// <summary>A new key signs every phone out. The app hands it to the server as soon as it's saved.</summary>
    public void UnpairAll()
    {
        _settings.RemoteKey = RemoteSignature.NewKey();
        UnpairHint = "Done. Every phone is signed out. Pair again with the code above.";
    }

    /// <summary>Re-reads everything. The app calls it after starting or stopping the server.</summary>
    public void Refresh()
    {
        var enabled = _settings.RemoteEnabled;
        if (enabled != _watchingNetwork)
        {
            // Only hold on to the timer and the network event while the remote is on.
            if (enabled)
            {
                NetworkChange.NetworkAddressChanged += OnNetworkAddressChanged;
                _timer.Start();
            }
            else
            {
                NetworkChange.NetworkAddressChanged -= OnNetworkAddressChanged;
                _timer.Stop();
                UnpairHint = UnpairIdle;
            }

            _watchingNetwork = enabled;
        }

        (StatusText, Tone) = _server.State switch
        {
            RemoteServerState.Listening => ($"Listening on port {_server.Port}.", StatusTone.Green),
            RemoteServerState.Failed => ($"{_server.Error} Turn the phone remote off and on to try again.", StatusTone.Amber),
            _ => ("Off.", StatusTone.Gray),
        };

        if (enabled)
        {
            Addresses = FindAddresses(_settings.RemotePort);
            RefreshCode();
        }
    }

    public void Dispose()
    {
        _timer.Stop();
        NetworkChange.NetworkAddressChanged -= OnNetworkAddressChanged;
    }

    private void RefreshCode()
    {
        var current = _pairing.Current;
        Code = $"{current.Code[..3]} {current.Code[3..]}";

        var now = DateTimeOffset.UtcNow;
        if (_pairing.LockedUntil is { } lockedUntil)
        {
            CodeHint = $"Too many wrong codes. Try again in {Humanize.Duration(lockedUntil - now + TimeSpan.FromSeconds(1))}.";
            return;
        }

        // Whole minutes round up, so a fresh code says "10 min" rather than "9 min".
        var left = current.ExpiresAt - now;
        CodeHint = "Valid for " + Humanize.Duration(left >= TimeSpan.FromMinutes(1) ? TimeSpan.FromMinutes(Math.Ceiling(left.TotalMinutes)) : left);
    }

    private void OnNetworkAddressChanged(object? sender, EventArgs e) =>
        _timer.Dispatcher.InvokeAsync(() =>
        {
            if (_settings.RemoteEnabled)
                Addresses = FindAddresses(_settings.RemotePort);
        });

    /// <summary>
    /// This PC's IPv4 addresses on networks that are up. Networks with a gateway, usually the Wi-Fi or
    /// cable to the router, come first; adapters for virtual machines and VPNs rarely reach a phone.
    /// </summary>
    private static RemoteAddress[] FindAddresses(int port)
    {
        try
        {
            return NetworkInterface.GetAllNetworkInterfaces()
                .Where(network => network.OperationalStatus == OperationalStatus.Up &&
                    network.NetworkInterfaceType is not (NetworkInterfaceType.Loopback or NetworkInterfaceType.Tunnel))
                .SelectMany(network =>
                {
                    var properties = network.GetIPProperties();
                    var hasGateway = properties.GatewayAddresses.Any(gateway =>
                        gateway.Address.AddressFamily == AddressFamily.InterNetwork && !gateway.Address.Equals(IPAddress.Any));
                    return properties.UnicastAddresses
                        .Select(unicast => unicast.Address)
                        .Where(address => address.AddressFamily == AddressFamily.InterNetwork &&
                            !IPAddress.IsLoopback(address) && !IsLinkLocal(address))
                        .Select(address => (Address: address, network.Name, hasGateway));
                })
                .OrderByDescending(found => found.hasGateway)
                .Select(found => new RemoteAddress($"{found.Address}:{port}", found.Name))
                .ToArray();
        }
        catch (NetworkInformationException)
        {
            return [];
        }
    }

    /// <summary>169.254.x.x: what Windows picks when no network handed out an address.</summary>
    private static bool IsLinkLocal(IPAddress address) => address.GetAddressBytes() is [169, 254, ..];
}
