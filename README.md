# Lerua Zakup

Lerua Zakup is an Android application built with Flutter. The first offline scaffold is implemented; business workflows and MoySklad synchronization will be added in later milestones.

## Implemented in the offline foundation

- Home screen with the six agreed actions and placeholder feedback.
- Compact weekly strip and full-screen monthly calendar.
- Light, dark, and system themes with persistent settings.
- Masked API-token storage using Android secure storage.
- Android back navigation, exit confirmation, and restoration support.
- Full-screen portrait mode and notification permission groundwork.
- Live internet-availability indicator (red = no validated internet, yellow = internet available).
- Low-storage warning when available internal storage falls below 500 MiB, rate-limited to once per 24 hours.

The current offline release does **not** send requests to MoySklad. The indicator never turns green until API reachability is implemented and confirmed.

## Download

[Download Lerua Zakup 1.0.0 offline APK](https://github.com/Olega20/Lerua_Zakup/releases/download/v1.0.0-offline/app-release.apk)

This prerelease APK is signed with the Android debug certificate for internal installation and testing. It is not a Play Store production-signed build. Physical-device verification is pending.

## Requirements

- Flutter 3.47.6 (stable)
- Dart 3.13.5
- Android SDK and Android build tools
- Java 17-compatible Android toolchain

## Getting started

1. Clone this repository.
2. Open the project directory.
3. Fetch dependencies:

   ```bash
   flutter pub get
   ```

4. Run static analysis and all unit/widget tests:

   ```bash
   flutter analyze
   flutter test
   ```

5. Run the Android integration smoke test on a connected Android device or emulator:

   ```bash
   flutter test integration_test
   ```

6. Build a debug or release APK:

   ```bash
   flutter build apk --debug
   flutter build apk --release
   ```

APK files are written to `build/app/outputs/flutter-apk/`.

## Android application ID

`com.olega20.leruazakup`

## Project documentation

- [Agreed requirements](docs/requirements/AGREED_REQUIREMENTS.md)
- [Startup design](docs/superpowers/specs/2026-11-19-lerua-zakup-startup-design.md)
- [Startup implementation plan](docs/superpowers/plans/2026-11-19-lerua-zakup-startup.md)
- [Offline release verification checklist](docs/release/OFFLINE_RELEASE_CHECKLIST.md)
