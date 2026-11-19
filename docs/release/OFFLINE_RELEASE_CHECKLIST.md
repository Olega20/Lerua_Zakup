# Lerua Zakup — offline release verification

Version: `1.0.0+1`  
Application ID: `com.olega20.leruazakup`

## Automated verification

- [x] Full Flutter unit/widget suite: 92 tests passed after Task 7.
- [x] Dart formatting check: no files changed.
- [x] `flutter analyze`: no issues found.
- [x] Android debug APK build completed successfully after Task 7.
- [ ] Final full-suite run after Task 8 integration smoke test.
- [ ] Final release APK build and artifact inspection.
- [ ] GitHub Release publication.

## Device verification — intentionally deferred

The user requested that all physical-device checks be performed after the complete offline scaffold is assembled. No Android device was connected during the current automated verification.

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
