# KeepGreen for Android

Android can't send input to other apps, so the Android app does two honest things:

- **My computers** is a remote for KeepGreen on your Windows PC or Mac on the same Wi-Fi. See the status, flip the switch, start or cancel a boost. It speaks the [KeepGreen Remote API](../docs/remote-api.md).
- **This phone** keeps this phone's screen awake for a while, so Teams (or Slack, or Zoom) stays Available while it's open on screen. It has a timer, an ongoing notification with a Stop button, and a Quick Settings tile.

No accounts, no cloud, no telemetry. The app only talks to computers you pair on your local network.

## Build

You need JDK 17 and the Android SDK (API 35).

**Android Studio:** open this `android` folder and run the `app` configuration.

**Command line:** with Gradle 8.11 installed (this project doesn't ship a Gradle wrapper):

```sh
cd android
gradle assembleDebug testDebugUnitTest
```

The debug APK lands in `app/build/outputs/apk/debug/`.

## Pairing

1. On the computer, open KeepGreen → Settings → Phone remote and turn it on.
2. On the phone, tap **Add computer** and type the address and 6-digit code it shows, or scan the QR code (macOS) to open a `keepgreen://pair` link.

The shared key is stored in the app's private storage and excluded from backups. Removing a computer only forgets it on this phone; *Unpair all phones* on the computer signs every phone out.

## Keeping the screen awake

KeepGreen holds the screen on with an invisible 1×1 window when you allow *Display over other apps*, and with an older screen wake lock otherwise. It never touches other apps.
