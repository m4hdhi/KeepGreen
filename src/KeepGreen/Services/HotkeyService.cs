using System.Windows;
using System.Windows.Interop;
using KeepGreen.Native;

namespace KeepGreen.Services;

/// <summary>A system-wide Ctrl + Alt + G shortcut that works even while the window is hidden.</summary>
internal sealed class HotkeyService : IDisposable
{
    private const int HotkeyId = 0x4B47;
    private const int WM_HOTKEY = 0x0312;
    private const uint MOD_ALT = 0x0001;
    private const uint MOD_CONTROL = 0x0002;
    private const uint MOD_NOREPEAT = 0x4000;
    private const uint VK_G = 0x47;

    private readonly HwndSource _source;
    private readonly Action _onPressed;

    public HotkeyService(Window window, Action onPressed)
    {
        _onPressed = onPressed;
        var handle = new WindowInteropHelper(window).EnsureHandle();
        _source = HwndSource.FromHwnd(handle);
        _source.AddHook(WndProc);
    }

    public bool IsRegistered { get; private set; }

    /// <returns>Whether the shortcut is registered; false if another app already owns it.</returns>
    public bool SetEnabled(bool enabled)
    {
        if (enabled && !IsRegistered)
        {
            IsRegistered = NativeMethods.RegisterHotKey(_source.Handle, HotkeyId, MOD_CONTROL | MOD_ALT | MOD_NOREPEAT, VK_G);
        }
        else if (!enabled && IsRegistered)
        {
            NativeMethods.UnregisterHotKey(_source.Handle, HotkeyId);
            IsRegistered = false;
        }

        return IsRegistered;
    }

    public void Dispose()
    {
        SetEnabled(false);
        if (!_source.IsDisposed)
            _source.RemoveHook(WndProc);
    }

    private nint WndProc(nint hwnd, int msg, nint wParam, nint lParam, ref bool handled)
    {
        if (msg == WM_HOTKEY && wParam == HotkeyId)
        {
            _onPressed();
            handled = true;
        }

        return 0;
    }
}
