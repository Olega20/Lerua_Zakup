# Lerua Zakup — offline release verification

Version: `1.0.0+1`  
Application ID: `com.olega20.leruazakup`

## Automated verification

- [x] Full Flutter unit/widget suite: 94 tests passed after Task 8 host smoke coverage.
- [x] Dart formatting check: no files changed.
- [x] `flutter analyze`: no issues found.
- [x] Android debug APK build completed successfully after Task 7.
- [x] Final full-suite run after Task 8 host smoke test: 94 tests passed.
- [x] Debug APK built (211,946,468 bytes).
- [x] Release APK built (50,389,444 bytes; 48.1 MiB).
- [x] Release package verified: `com.olega20.leruazakup`, version `1.0.0` / code `1`.
- [x] APK v2 signature verified; signer is Android Debug certificate (not a production signing key).
- [x] Release SHA-256: `2728D593B253FF94DF598016F44C20FCE74D37A396BF003B87EADDF0BC4110E1`.
- [x] GitHub Release published: [v1.0.0-offline](https://github.com/Olega20/Lerua_Zakup/releases/tag/v1.0.0-offline).
- [x] APK asset uploaded and verified: [app-release.apk](https://github.com/Olega20/Lerua_Zakup/releases/download/v1.0.0-offline/app-release.apk).

## Device verification — intentionally deferred

The user requested that all physical-device checks be performed after the complete offline scaffold is assembled. No Android device or emulator was available during the current automated verification. The user asked to defer physical-device checks until the complete offline scaffold is assembled.

- [ ] Fresh install and first launch.
- [ ] Notification permission grant and denial behavior.
- [ ] Immersive mode, system gestures, and portrait lock.
- [ ] Light/dark/system theme selection and persistence across app restart.
- [ ] Secure API-token save, masking, delete, and settings reset.
- [ ] Calendar navigation, date/time/timezone changes, and process restoration.
- [ ] Live internet loss/recovery and red/yellow indicator transitions.
- [ ] Low-storage Snackbar behavior on a device with less than 500 MiB available.
- [ ] App update preserves settings and token.
- [ ] Uninstall removes local data and secure token.

## Scope notes

- The offline scaffold does not call the MoySklad API.
- Green connectivity status is intentionally unavailable until API reachability checking is implemented.
- Business sections and Warehouse Journal remain placeholders.
- Device-dependent checks are pending, not claimed as passed.
