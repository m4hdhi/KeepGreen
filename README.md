<p align="center">
  <img src="docs/banner.png" alt="KeepGreen: stay available on your schedule, automatically" width="100%">
</p>

<p align="center">
  <a href="https://github.com/m4hdhi/KeepGreen/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/m4hdhi/KeepGreen?color=22c55e&label=download"></a>
  <a href="https://github.com/m4hdhi/KeepGreen/actions/workflows/ci.yml"><img alt="CI" src="https://img.shields.io/github/actions/workflow/status/m4hdhi/KeepGreen/ci.yml?branch=main&label=build"></a>
  <img alt="Windows 10 and 11" src="https://img.shields.io/badge/Windows-10%20%7C%2011-0078d4">
  <img alt=".NET 10" src="https://img.shields.io/badge/.NET-10-512bd4">
  <a href="LICENSE"><img alt="MIT license" src="https://img.shields.io/github/license/m4hdhi/KeepGreen?color=22c55e"></a>
</p>

**KeepGreen** keeps your PC awake and your Microsoft Teams, Slack and Zoom status *Available*, but only during **your** work hours. Stepping away for coffee no longer turns you yellow, your PC doesn't fall asleep mid-download, and when the workday ends KeepGreen switches itself off.

It is not a mouse jiggler that shoves your cursor around on a timer. KeepGreen watches the same Windows idle timer that Teams watches. It does nothing while you work, and only sends one invisible signal after you've actually gone quiet.

<p align="center">
  <img src="docs/screenshot-dashboard.png" alt="KeepGreen dashboard" width="88%">
</p>

## Features

**Smart, not noisy**
- **Idle-aware nudges.** KeepGreen acts only after you've been idle for the time you choose (15 s to 4 min), so it never fights your mouse or keyboard.
- **Invisible by default.** A zero-distance mouse signal resets the idle timer without moving your cursor. Prefer something else? Use *Micro-move* (1 px and back) or *Phantom key* (F15, a key no keyboard has).
- **Proof it works.** The built-in self-test sends one nudge and confirms Windows registered it. If Windows ever starts ignoring nudges (an app running as administrator is in front, for example), KeepGreen warns you instead of failing silently.
- **Awake-only mode** keeps the PC and screen on without touching your status.

**On your schedule**
- **Working days and hours.** Each day has its own hours, with presets for *Mon–Fri 9–17*, *Mon–Fri 8–18* or *every day*.
- **Night shifts.** An end time before the start time simply runs past midnight.
- **Lunch break.** Let your status go Away while you eat.
- **Days off.** Add holidays and vacation days, and past ones clean themselves up.
- **Quick boosts.** Stay green for 15 min, 30 min, 1 h, 2 h or *until the end of my workday*, even outside your schedule.

**Thoughtful pauses**
- Pauses when you **lock your PC**, because you really are away.
- Pauses **on battery** or **below a battery level** you pick, so your laptop isn't drained.
- **App-aware:** optionally works only while `ms-teams`, Slack or Zoom are running.
- Survives **sleep and Modern Standby**, re-asserting itself after every resume.

**Feels native**
- Windows 11 Fluent design with Mica, light and dark themes, and a green accent.
- A **status dot in the tray** that changes colour, with every action on right-click.
- **Ctrl + Alt + G** toggles it from anywhere.
- **Start with Windows**, straight to the tray. No admin rights needed.
- Notifications when work hours start or end, or a boost runs out.
- One portable `.exe`, settings in plain JSON, **no telemetry, no network access, no account.**

<p align="center">
  <img src="docs/screenshot-schedule.png" alt="KeepGreen schedule" width="49%">
  <img src="docs/screenshot-behavior.png" alt="KeepGreen behavior settings" width="49%">
</p>

## Download

1. Grab the latest build from **[Releases](https://github.com/m4hdhi/KeepGreen/releases/latest)**:
   - `KeepGreen-win-x64-standalone.exe`: runs anywhere, nothing else to install.
   - `KeepGreen-win-x64.exe`: a tiny download that needs the [.NET 10 Desktop Runtime](https://dotnet.microsoft.com/download/dotnet/10.0).
2. Run it. Turn on **Start with Windows** under *Settings* and you're done.

> Windows SmartScreen may warn about a new, unsigned app. Choose **More info → Run anyway**, or build it yourself from source below.

## How it works

| Need | How KeepGreen does it |
| --- | --- |
| Keep the PC awake | Holds a [`SetThreadExecutionState`](https://learn.microsoft.com/windows/win32/api/winbase/nf-winbase-setthreadexecutionstate) request while active, and releases it the moment it stops. |
| Keep your status *Available* | Reads the Windows idle time via [`GetLastInputInfo`](https://learn.microsoft.com/windows/win32/api/winuser/nf-winuser-getlastinputinfo), the same signal Teams uses, and sends one tiny [`SendInput`](https://learn.microsoft.com/windows/win32/api/winuser/nf-winuser-sendinput) event only when you pass your idle threshold. |
| Know when to work | A pure, unit-tested policy combines your switch, schedule, lunch break, days off, boosts, lock state, battery and running apps. |
| Never fail silently | Every nudge is verified a second later by checking that the idle timer really reset. |

Teams switches to *Away* after about five minutes without input. KeepGreen's slowest setting (4 minutes, ±20%) still nudges in time.

## Build from source

You need Windows and the [.NET 10 SDK](https://dotnet.microsoft.com/download/dotnet/10.0).

```powershell
git clone https://github.com/m4hdhi/KeepGreen.git
cd KeepGreen
dotnet run --project src/KeepGreen                # run the app
dotnet run --project tests/KeepGreen.Tests        # run the tests
```

Publish a single-file build:

```powershell
dotnet publish src/KeepGreen -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -o out
```

Project layout:

```
src/KeepGreen.Core     schedule, presence policy and settings; plain .NET, fully unit-tested
src/KeepGreen          the WPF app: engine, tray, hotkey and the Fluent UI (WPF-UI)
tests/KeepGreen.Tests  dependency-free tests for the core
tools/make-assets.ps1  renders the logo, icon and banner from code
```

A Debug build can re-render the README screenshots off-screen with sample data: `KeepGreen.exe --screenshots docs`.

## FAQ

**Does it work with Slack, Zoom or Discord?** Yes. Desktop apps that decide you're away from the Windows idle timer see KeepGreen's nudges. Chat apps running inside a browser tab may use their own activity checks.

**Will it type into my documents or move my cursor?** No. *Invisible* sends a zero-distance mouse event, and *Phantom key* uses F15, which ordinary apps ignore. Both happen only while you're idle.

**Can it keep me green while my PC is locked?** It pauses on lock by default, because a locked PC means you're away. You can turn that off, but many company policies lock the PC anyway.

**Where are my settings?** In `%APPDATA%\KeepGreen\settings.json`. Delete the folder to reset everything.

## Use it responsibly

KeepGreen changes how idle your PC looks, not how much you work. Follow your organization's IT and acceptable-use policies.

## Contributing

Issues and pull requests are welcome. If you're adding behaviour, put the logic in `KeepGreen.Core` with a test in `tests/KeepGreen.Tests`.

## License

[MIT](LICENSE) © 2026 [Mahdhi Muzammil](https://github.com/m4hdhi)

<p align="center"><b>If KeepGreen saves your green dot, give it a ⭐. It really helps!</b></p>
