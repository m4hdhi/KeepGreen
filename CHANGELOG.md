# Changelog

## 2.0.0

KeepGreen goes multi-platform.

- **macOS app:** a native SwiftUI menu-bar app with the same schedule, boosts, smart pauses, stats and self-test as Windows.
- **Phone remote:** new iPhone and Android apps show your computer's live status and let you flip the switch or start and cancel boosts. Pair once with a 6-digit code (or a QR code on the Mac). Off by default, local Wi-Fi only, every command signed. See [docs/remote-api.md](docs/remote-api.md).
- **Android keep-awake:** keep the phone's screen on for a while or until you turn it off, from the app or a Quick Settings tile.
- **Windows:** a new *Phone remote* section in Settings. The self-test now waits until you're hands-off, so it can't pass just because you clicked the button.
- Shared Swift core (`KeepGreenKit`) with tests that mirror the C# ones, and CI that builds and tests Windows, macOS, iOS and Android on every change.

## 1.0.0 (2026-11-05)

First release.

- Idle-aware nudges: KeepGreen only acts after you've been idle, never while you work.
- Three nudge styles (Invisible, Micro-move, Phantom key) plus an Awake-only mode.
- Weekly work schedule with per-day hours, night shifts, a lunch break and days off.
- Quick boosts from the dashboard or tray: 15 min to 2 hours, or until the end of your workday.
- Smart pauses: when the PC is locked, on battery, on low battery, or until your chat apps are running.
- Built-in self-test, and a warning when Windows blocks nudges because an admin window is in front.
- Tray status dot, notifications, Ctrl + Alt + G shortcut, start with Windows, light and dark themes.
