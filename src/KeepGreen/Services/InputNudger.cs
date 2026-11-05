using System.Runtime.InteropServices;
using KeepGreen.Core;
using static KeepGreen.Native.NativeMethods;

namespace KeepGreen.Services;

/// <summary>Sends the tiny synthetic input that resets the Windows idle timer.</summary>
internal static class InputNudger
{
    private const ushort VK_F15 = 0x7E;

    /// <returns>False when Windows refused the input, for example because an elevated window is in front.</returns>
    public static bool Send(NudgeStyle style)
    {
        INPUT[] inputs = style switch
        {
            NudgeStyle.MicroMove => [Mouse(1, 1), Mouse(-1, -1)],
            NudgeStyle.PhantomKey => [Key(VK_F15, 0), Key(VK_F15, KEYEVENTF_KEYUP)],
            _ => [Mouse(0, 0)],
        };

        var sent = SendInput((uint)inputs.Length, inputs, Marshal.SizeOf<INPUT>());
        return sent == inputs.Length;
    }

    private static INPUT Mouse(int dx, int dy) => new()
    {
        type = INPUT_MOUSE,
        U = new InputUnion { mi = new MOUSEINPUT { dx = dx, dy = dy, dwFlags = MOUSEEVENTF_MOVE } },
    };

    private static INPUT Key(ushort virtualKey, uint flags) => new()
    {
        type = INPUT_KEYBOARD,
        U = new InputUnion { ki = new KEYBDINPUT { wVk = virtualKey, dwFlags = flags } },
    };
}
