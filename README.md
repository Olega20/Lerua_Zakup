# Lerua Zakup

Lerua Zakup is an Android application built with Flutter. The first milestone establishes the Android project scaffold; business features are being added incrementally.

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

4. Run static analysis and tests:

   ```bash
   flutter analyze
   flutter test
   ```

5. Build a debug APK:

   ```bash
   flutter build apk --debug
   ```

The debug APK is written to `build/app/outputs/flutter-apk/app-debug.apk`.

## Android application ID

`com.olega20.leruazakup`

## Project status

The initial scaffold is in place. The app's agreed home screen, calendar, settings, navigation, and offline-first foundations will be implemented in subsequent reviewed milestones.

## Documentation

- [Agreed requirements](docs/requirements/AGREED_REQUIREMENTS.md)
- [Startup design](docs/superpowers/specs/2026-11-19-lerua-zakup-startup-design.md)
- [Startup implementation plan](docs/superpowers/plans/2026-11-19-lerua-zakup-startup.md)
