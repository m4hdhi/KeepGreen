using System.ComponentModel;
using KeepGreen.Core;
using KeepGreen.Native;
using Drawing = System.Drawing;
using Forms = System.Windows.Forms;

namespace KeepGreen.Services;

/// <summary>The status dot in the notification area, with quick actions on right-click.</summary>
internal sealed class TrayIconService : IDisposable
{
    private readonly PresenceEngine _engine;
    private readonly AppSettings _settings;
    private readonly Forms.NotifyIcon _notifyIcon;
    private readonly Forms.ContextMenuStrip _menu;
    private readonly Forms.ToolStripMenuItem _header;
    private readonly Forms.ToolStripMenuItem _toggle;
    private readonly Forms.ToolStripMenuItem _cancelBoost;
    private readonly Dictionary<StatusTone, Drawing.Icon> _icons;
    private StatusTone? _shownTone;
    private string _shownText = "";

    public TrayIconService(PresenceEngine engine, AppSettings settings, Action open, Action quit)
    {
        _engine = engine;
        _settings = settings;
        _icons = Enum.GetValues<StatusTone>().ToDictionary(tone => tone, tone => CreateDotIcon(StatusPalette.ColorOf(tone)));

        _menu = new Forms.ContextMenuStrip();
        _header = new Forms.ToolStripMenuItem { Enabled = false };
        _toggle = new Forms.ToolStripMenuItem("", null, (_, _) => _settings.IsEnabled = !_settings.IsEnabled)
        {
            ShortcutKeyDisplayString = "Ctrl+Alt+G",
        };

        var boost = new Forms.ToolStripMenuItem("Keep me green for");
        foreach (var (label, minutes) in new[] { ("15 minutes", 15), ("30 minutes", 30), ("1 hour", 60), ("2 hours", 120) })
            boost.DropDownItems.Add(label, null, (_, _) => _engine.Boost(TimeSpan.FromMinutes(minutes)));
        boost.DropDownItems.Add("Until the end of my workday", null, (_, _) => _engine.BoostUntilEndOfWorkday());
        _cancelBoost = new Forms.ToolStripMenuItem("Cancel boost", null, (_, _) => _engine.CancelBoost());

        var openItem = new Forms.ToolStripMenuItem("Open KeepGreen", null, (_, _) => open());
        openItem.Font = new Drawing.Font(_menu.Font, Drawing.FontStyle.Bold);

        _menu.Items.AddRange(new Forms.ToolStripItem[]
        {
            _header,
            new Forms.ToolStripSeparator(),
            _toggle,
            boost,
            _cancelBoost,
            new Forms.ToolStripSeparator(),
            openItem,
            new Forms.ToolStripMenuItem("Quit", null, (_, _) => quit()),
        });
        _menu.Opening += (_, _) => RefreshMenu();

        _notifyIcon = new Forms.NotifyIcon { ContextMenuStrip = _menu, Visible = true };
        _notifyIcon.MouseClick += (_, e) =>
        {
            if (e.Button == Forms.MouseButtons.Left)
                open();
        };

        _engine.PropertyChanged += OnEngineChanged;
        Refresh();
    }

    public void ShowNotification(string title, string message) =>
        _notifyIcon.ShowBalloonTip(5000, title, message, Forms.ToolTipIcon.None);

    public void Dispose()
    {
        _engine.PropertyChanged -= OnEngineChanged;
        _notifyIcon.Visible = false;
        _notifyIcon.Dispose();
        _menu.Dispose();
        foreach (var icon in _icons.Values)
            icon.Dispose();
    }

    private void OnEngineChanged(object? sender, PropertyChangedEventArgs e) => Refresh();

    private void Refresh()
    {
        var tone = StatusPalette.ToneOf(_engine.State);
        if (tone != _shownTone)
        {
            _notifyIcon.Icon = _icons[tone];
            _shownTone = tone;
        }

        // The tooltip is limited to 127 characters.
        var text = $"KeepGreen: {_engine.Headline}";
        if (text.Length > 120)
            text = text[..120];
        if (text != _shownText)
        {
            _notifyIcon.Text = text;
            _shownText = text;
        }
    }

    private void RefreshMenu()
    {
        _header.Text = _engine.Headline;
        _toggle.Text = _settings.IsEnabled ? "Turn off" : "Turn on";
        _cancelBoost.Visible = _engine.HasBoost;
    }

    private static Drawing.Icon CreateDotIcon(System.Windows.Media.Color color)
    {
        var fill = Drawing.Color.FromArgb(color.R, color.G, color.B);
        using var bitmap = new Drawing.Bitmap(32, 32);
        using (var graphics = Drawing.Graphics.FromImage(bitmap))
        {
            graphics.SmoothingMode = Drawing.Drawing2D.SmoothingMode.AntiAlias;
            using var halo = new Drawing.SolidBrush(Drawing.Color.FromArgb(90, fill));
            graphics.FillEllipse(halo, 1, 1, 30, 30);
            using var dot = new Drawing.SolidBrush(fill);
            graphics.FillEllipse(dot, 6, 6, 20, 20);
            using var rim = new Drawing.Pen(Drawing.Color.White, 2.5f);
            graphics.DrawEllipse(rim, 6, 6, 20, 20);
        }

        var handle = bitmap.GetHicon();
        try
        {
            using var temporary = Drawing.Icon.FromHandle(handle);
            return (Drawing.Icon)temporary.Clone();
        }
        finally
        {
            NativeMethods.DestroyIcon(handle);
        }
    }
}
