# Lerua Zakup Startup Version Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the approved offline-first Android Flutter application with its home screen, calendar, settings, secure token storage, connectivity indicator, and Android lifecycle behavior.

**Architecture:** Use the selected modular feature-first structure. Keep app composition and shared platform services separate from feature modules; implement only the real offline functionality in this release and leave future business features as lightweight placeholders.

**Tech Stack:** Flutter/Dart, Flutter widget and unit tests, Android platform integration. Add only verified compatible packages for preferences, secure storage, connectivity, notifications, app version, and storage capacity after checking the installed Flutter/Dart toolchain.

**Spec:** `docs/superpowers/specs/2026-11-19-lerua-zakup-startup-design.md`

## Global Constraints

- Platform: Android; UI and primary logic: Flutter/Dart.
- Target environment recorded in the spec: Flutter 3.47.6, Dart 3.13.5, Android SDK `D:\Android\Sdk`; local directory `D:\src\Lerua_Zakup`.
- Repository: `Olega20/Lerua_Zakup`, branch `main`; source changes are made directly through GitHub.
- Do not modify or use `Olega20/zakupki_app` as the application base.
- New application package name must differ from the old application; exact package name is an explicit pre-scaffold decision.
- First launch theme: light. Supported theme choices: Light, Dark, System.
- UI language: Russian; date format `ДД.ММ.ГГГГ`; time format 24-hour.
- First release is offline: no MySklad API requests, no business-operation queue, and no real warehouse journal.
- API token must only be stored in Android secure storage and must never be logged or exposed in clear text.
- Main screen is the normal launch destination; preserve current screen while the Android task is retained, and restore system-saved state after OS process recreation only when Android supplies it.
- Portrait orientation only; immersive full-screen behavior must retain Android system gestures.
- Every task must include tests, verification, and a Git commit. Do not begin the next task until the current task is reviewed and accepted.

## Review Focus

1. **Malformed or missing persisted preferences:** app must fall back to System theme without crashing; pin with settings repository tests.
2. **Secure-storage unavailable or failing:** token entry must remain in the field until leaving Settings, show a short error, and never leak to logs; pin with token controller tests.
3. **Connectivity stream emits duplicate, null-like, or rapidly changing states:** indicator must render only red when offline and yellow when online; pin with connectivity state tests.
4. **Android process recreation versus explicit app exit:** restore only when the system restores the retained task; a fresh launch after explicit exit starts at Home; pin with navigation/lifecycle tests and manual Android verification.
5. **Small display, large system font, and insufficient free storage:** UI remains usable and storage warning is non-blocking; pin with responsive widget tests and storage-warning policy tests.

---

## File Structure

Create the following focused structure as the project is implemented:

```
lib/
  main.dart
  app/
    app.dart
    app_theme.dart
    app_router.dart
    app_lifecycle.dart
  core/
    errors/app_error.dart
    feedback/snackbar_service.dart
    storage/preferences_store.dart
    storage/secure_token_store.dart
    notifications/notification_service.dart
    platform/storage_capacity_service.dart
    widgets/...
  features/
    home/presentation/home_screen.dart
    calendar/domain/calendar_date.dart
    calendar/presentation/...
    settings/data/settings_repository.dart
    settings/domain/app_settings.dart
    settings/presentation/...
    connectivity/data/connectivity_monitor.dart
    connectivity/domain/connectivity_status.dart
    connectivity/presentation/connectivity_indicator.dart
    purchase/presentation/placeholder_screen.dart
    order/presentation/placeholder_screen.dart
    transfer/presentation/placeholder_screen.dart
    inventory/presentation/placeholder_screen.dart
    other_actions/presentation/placeholder_screen.dart
    warehouse_log/presentation/warehouse_log_placeholder.dart
test/
  core/
  features/
integration_test/
  app_smoke_test.dart
```

A shared placeholder widget may be used instead of duplicating the same file in each placeholder feature. Keep the module boundaries from the approved design; adjust exact filenames only when the actual Flutter project conventions require it, and record the adjustment in the task commit.

## Task 1: Verify toolchain and establish the Flutter project

**Files:**
- Create: Flutter project scaffold and platform files at repository root.
- Create: `.gitignore` (only if not generated correctly).
- Modify: `README.md` with verified local setup and run instructions.
- Test: generated Flutter smoke test.

**Interfaces:**
- Produces the Android application identifier and a clean, runnable Flutter project for all later tasks.
- Before scaffolding, inspect the old app only to determine its existing package identifier; do not copy its source or configuration.

- [ ] **Step 1: Verify local Flutter, Dart, and Android SDK versions**

Run in PowerShell:
```powershell
flutter --version
dart --version
flutter doctor -v
```
Expected: record actual installed versions and Android toolchain status. If the installed versions differ from the target recorded in the spec, stop and report the difference before creating the project.

- [ ] **Step 2: Determine and record a unique Android application ID**

Inspect the old application's package identifier as reference only. Choose a distinct reverse-domain identifier for Lerua Zakup and record it in the README and project configuration. Do not guess an identifier silently.

- [ ] **Step 3: Create the Flutter project**

Run from `D:\src\Lerua_Zakup` using the chosen application ID:
```powershell
flutter create --org <chosen-org> --project-name lerua_zakup .
```
Set the Android applicationId/namespace to the chosen unique identifier and set the visible app label to `Lerua Zakup`.

- [ ] **Step 4: Run the generated test and Android debug build**

Run:
```powershell
flutter test
flutter build apk --debug
```
Expected: generated test passes and debug APK builds successfully.

- [ ] **Step 5: Commit the scaffold**

Commit: `chore: create Flutter Android application scaffold`.

## Task 2: App composition, theme, navigation shell, and shared feedback

**Files:**
- Create: `lib/main.dart`, `lib/app/app.dart`, `lib/app/app_theme.dart`, `lib/app/app_router.dart`.
- Create: `lib/core/feedback/snackbar_service.dart`, shared placeholder widget.
- Test: `test/app/app_theme_test.dart`, `test/app/app_navigation_test.dart`, `test/core/feedback/snackbar_service_test.dart`.

**Interfaces:**
- `AppTheme`: provides light, dark, and system ThemeData.
- `AppRouter`: maps Home, Full Calendar, Settings, and placeholder destinations; prevents duplicate pushes for the active destination.
- `SnackbarService.show(BuildContext context, String message)`: shows a bottom Snackbar for at most five seconds and dismisses it on any screen tap.

- [ ] **Step 1: Write failing theme tests** for Light, Dark, and System selection, including live system brightness changes.
- [ ] **Step 2: Run the theme tests** and confirm they fail because the app theme module is not implemented.
- [ ] **Step 3: Implement app bootstrap and theme selection** with Light as the initial default; persistency is added in Task 5.
- [ ] **Step 4: Write failing navigation and Snackbar tests**: route replacement/push behavior, no duplicate active destination, bottom placement, five-second maximum, tap-to-dismiss.
- [ ] **Step 5: Run those tests** and confirm the missing behaviors fail.
- [ ] **Step 6: Implement the navigation shell and shared Snackbar service** without adding feature-specific business logic.
- [ ] **Step 7: Run**
```powershell
flutter test test/app test/core/feedback
```
Expected: all tests pass.
- [ ] **Step 8: Commit** `feat: add app shell theme navigation and feedback`.

## Task 3: Calendar domain and calendar UI

**Files:**
- Create: `lib/features/calendar/domain/calendar_date.dart`, date formatting and month-grid helpers.
- Create: `lib/features/calendar/presentation/week_strip.dart`, `full_calendar_screen.dart`, date selection/list widgets.
- Test: `test/features/calendar/domain/calendar_date_test.dart`, `test/features/calendar/presentation/week_strip_test.dart`, `full_calendar_screen_test.dart`.

**Interfaces:**
- `CalendarDate.today(DateTime now)`: obtains the local calendar date.
- `CalendarDate.monthGrid(int year, int month)`: returns week rows starting Monday, including adjacent-month dates, with only the rows needed for the month.
- Calendar widgets receive the current date and selected date explicitly; they do not read global time directly.

- [ ] **Step 1: Write failing date-domain tests** for Monday-first weeks, month boundaries, leap years, row counts, adjacent-month dates, and Russian date formatting.
- [ ] **Step 2: Run the date tests** and verify the missing domain functions fail.
- [ ] **Step 3: Implement pure calendar date and month-grid functions**.
- [ ] **Step 4: Run domain tests** and verify they pass.
- [ ] **Step 5: Write failing widget tests** for the seven-day strip, selected-day styling, weekends, today outline, adjacent-month selection, month title/year rule, and empty operations text.
- [ ] **Step 6: Implement the week strip and full calendar** with horizontal one-month swipe navigation; swiping changes the displayed month but not the selected date, while tapping an adjacent-month date selects it and changes month.
- [ ] **Step 7: Add tests** that opening a new full-calendar screen starts at the current month and selects today; returning to Home resets the visible week to the current date.
- [ ] **Step 8: Run**
```powershell
flutter test test/features/calendar
```
Expected: all calendar domain and widget tests pass.
- [ ] **Step 9: Commit** `feat: add Russian weekly and full calendar views`.

## Task 4: Home screen and placeholder destinations

**Files:**
- Create: `lib/features/home/presentation/home_screen.dart`.
- Create: placeholder destination routing for Purchase, Order, Transfer, Inventory, Other Actions, and Warehouse Log.
- Test: `test/features/home/home_screen_test.dart`, `test/features/home/placeholder_navigation_test.dart`.

**Interfaces:**
- Home consumes the calendar week widget and connectivity indicator from Task 7.
- Placeholder destinations use the shared placeholder widget and the exact Snackbar text `Функция находится в разработке`.

- [x] **Step 1: Write failing Home widget tests** for top indicator slot, calendar above buttons, six identical text-only buttons, equal vertical distribution, no app-name header, and Russian labels.
- [x] **Step 2: Run tests** and confirm the Home screen is missing.
- [x] **Step 3: Implement Home layout** using responsive constraints, keeping the indicator slot reserved for Task 7.
- [x] **Step 4: Write failing placeholder tests** for all five business buttons and the Settings Journal placeholder; tapping must not open a blank screen and must show the exact Snackbar message.
- [x] **Step 5: Implement the lightweight placeholder destinations** and route behavior.
- [x] **Step 6: Run**
```powershell
flutter test test/features/home
```
Expected: Home layout and placeholder tests pass.
- [x] **Step 7: Commit** `feat: add home screen and placeholder sections`.

## Task 5: Settings, persistent preferences, secure token, and reset

**Files:**
- Create: `lib/core/storage/preferences_store.dart`, `lib/core/storage/secure_token_store.dart`.
- Create: `lib/features/settings/domain/app_settings.dart`, `data/settings_repository.dart`, settings presentation widgets/screen.
- Test: `test/core/storage/preferences_store_test.dart`, `secure_token_store_test.dart`, `test/features/settings/settings_repository_test.dart`, `settings_screen_test.dart`.

**Interfaces:**
- `PreferencesStore.readTheme() -> ThemeMode?`, `writeTheme(ThemeMode mode) -> Future<void>`, `clearUserPreferences() -> Future<void>`.
- `SecureTokenStore.readToken() -> Future<String?>`, `writeToken(String token) -> Future<void>`, `deleteToken() -> Future<void>`.
- `SettingsRepository.saveToken(String input) -> Future<SaveTokenResult>`: trims all whitespace before validation/storage; empty input returns an empty-input result and performs no write.
- `SettingsRepository.resetSettings({required bool confirmTokenDeletion})`: clears user preferences and deletes token only after the separate confirmation has been obtained by the UI.

- [x] **Step 1: Write failing storage/repository tests** for theme persistence, unreadable/invalid theme fallback to System, token masking state, whitespace stripping, empty token rejection, storage errors, and separate token-deletion confirmation during reset.
- [x] **Step 2: Run tests** and verify the missing stores/repository fail.
- [x] **Step 3: Implement preference and secure-token store adapters** using packages whose versions have been verified against the installed Flutter/Dart toolchain.
- [x] **Step 4: Implement SettingsRepository** and typed results; do not include token contents in exception messages or logs.
- [x] **Step 5: Run repository tests** and verify they pass, including injected secure-storage failures.
- [x] **Step 6: Write failing settings widget tests** for three theme buttons, masked token field with no reveal control, save/delete/reset confirmations, version display, Journal placeholder, and short error Snackbars.
- [x] **Step 7: Implement Settings screen**; successful token save leaves the field masked and populated, storage failure leaves the entered value in the field until leaving Settings.
- [x] **Step 8: Test persistence across repository recreation** and verify theme/token remain available after simulated app restart.
- [x] **Step 9: Run**
```powershell
flutter test test/core/storage test/features/settings
```
Expected: all storage and Settings tests pass.
- [x] **Step 10: Commit** `feat: add persistent settings and secure token storage`.

## Task 6: Android lifecycle, system UI, and notification permission preparation

**Files:**
- Modify: `lib/main.dart`, `lib/app/app_lifecycle.dart`, `lib/app/app_router.dart`.
- Create: `lib/core/notifications/notification_service.dart`.
- Modify: Android manifest and native configuration only as required for portrait, immersive UI, notification permission, and backup policy.
- Test: `test/app/app_lifecycle_test.dart`; Android integration/manual verification checklist.

**Interfaces:**
- `AppLifecycleController`: coordinates lifecycle notifications and restoration policy; it does not persist transient business drafts.
- `NotificationService.initializeAndRequestPermission()`: requests Android notification permission at first app launch, handles denial without blocking app use, and creates the app notification group/channel foundations without scheduling business notifications.

- [x] **Step 1: Write lifecycle tests** for retained task state, fresh launch to Home, and system-provided state restoration after process recreation.
- [x] **Step 2: Run lifecycle tests** and verify expected failures.
- [x] **Step 3: Implement lifecycle and navigation restoration behavior** without treating explicit exit as process death restoration.
- [x] **Step 4: Write notification service tests** for first-launch permission flow and denial.
- [x] **Step 5: Implement notification foundation** with standard Android sound defaults, grouping metadata, and no business notifications.
- [x] **Step 6: Configure Android portrait orientation, immersive sticky mode, system gesture compatibility, and backup exclusions** so secure token data is not restored from backup.
- [x] **Step 7: Run**
```powershell
flutter test test/app
flutter build apk --debug
```
Expected: tests pass and Android debug APK builds.
- [ ] **Step 8: Verify manually on Android**: system bars hidden, edge gestures still work, notification permission denial does not block app, task retained from Recents restores screen, fresh launch after explicit exit opens Home.
- [x] **Step 9: Commit** `feat: add Android lifecycle and notification foundation`.


**Manual verification note:** Step 8 remains open because no Android device was connected to ADB during this task (`adb devices -l` returned an empty device list). The Android debug APK builds successfully; immersive gesture behavior, the system permission dialog, and process/task restoration still require verification on the user's phone. Flutter restoration IDs now cover the Home selected day and the full calendar's selected date/visible month. Home also implements the agreed exit dialog and the two-second second-Back exit.

## Task 7: Connectivity indicator and low-storage warning

**Files:**
- Create: `lib/features/connectivity/domain/connectivity_status.dart`, `data/connectivity_monitor.dart`, `presentation/connectivity_indicator.dart`.
- Create: `lib/core/platform/storage_capacity_service.dart`, storage warning policy/controller.
- Test: `test/features/connectivity/connectivity_monitor_test.dart`, `connectivity_indicator_test.dart`, `test/core/platform/storage_capacity_service_test.dart`.

**Interfaces:**
- `ConnectivityStatus`: Offline or Online; no API-success state is exposed in this offline release.
- `ConnectivityMonitor.statuses`: stream of current internet availability; Offline maps to red, Online maps to yellow.
- `StorageCapacityService.getAvailableBytes() -> Future<int?>`: returns available bytes where Android supports it, otherwise null.
- `StorageWarningPolicy`: evaluates available capacity against a threshold selected and documented before implementation; warning is non-blocking and repeated warnings are rate-limited.

- [x] **Step 1: Confirm the low-storage threshold and repeat-warning policy.** Implementation default: warn when available internal data-partition storage is below **500 MiB**. This is an early-warning threshold aligned with Android's documented/AOSP low-storage threshold cap; it is not represented as a user-selected preference. If capacity is unavailable, do not warn. While storage remains below threshold, show at most one warning per **24 hours** (timestamp persisted across process restarts); if capacity recovers to the threshold or above, the next low-storage episode may warn immediately once the 24-hour cooldown has elapsed. Check at startup and whenever the app resumes. Research: Android's `DeviceStorageMonitorService` uses a configurable percentage threshold with a default 500 MB maximum cap; the exact OEM threshold can vary.
- [ ] **Step 2: Write failing connectivity tests** for offline red, online yellow, immediate offline transition, online recovery, and no API calls.
- [ ] **Step 3: Implement connectivity monitoring** with a compatible plugin and ensure duplicate events do not cause harmful UI churn.
- [ ] **Step 4: Write failing storage warning policy tests** for below-threshold, at-threshold, above-threshold, unavailable capacity, and rate limiting.
- [ ] **Step 5: Implement storage capacity lookup and non-blocking warning** with the documented threshold and Snackbar presentation.
- [ ] **Step 6: Integrate the indicator into Home** as a full-width 4 px strip above the calendar. Yellow is used whenever online; green is never shown in this release.
- [ ] **Step 7: Run**
```powershell
flutter test test/features/connectivity test/core/platform
```
Expected: all tests pass; code inspection confirms no MySklad HTTP requests or API token validation are present.
- [ ] **Step 8: Commit** `feat: add offline connectivity indicator and storage warning`.

## Task 8: Final integration, resilience, and release verification

**Files:**
- Modify: app composition and feature integration files as required.
- Create: `integration_test/app_smoke_test.dart`, release verification checklist under `docs/`.
- Test: all unit, widget, and integration tests.

**Interfaces:**
- Integrates all completed modules through the app composition root; no feature module reaches into another feature's private implementation.

- [ ] **Step 1: Write end-to-end smoke tests** for fresh launch to Home, navigation to Settings and back, calendar open/select/back, theme persistence, placeholder Snackbars, and connectivity strip.
- [ ] **Step 2: Run the integration tests** and record any failures before changes.
- [ ] **Step 3: Fix only integration defects** while preserving approved requirements; add regression tests for each fix.
- [ ] **Step 4: Run full quality checks**
```powershell
flutter analyze
flutter test
flutter test integration_test
flutter build apk --debug
flutter build apk --release
```
Expected: analyzer has no errors, all tests pass, and both APK builds succeed. Any warnings or unsupported integration-test environment limitations must be reported, not hidden.
- [ ] **Step 5: Verify on the target Android device when available**: fresh install, permission grant/denial, theme changes, secure token save/delete/reset, calendar navigation, system date/time changes, offline/online transition, app update preserving settings, and uninstall removing app data.
- [ ] **Step 6: Record actual test/build/device results** in the release checklist; do not claim unperformed checks.
- [ ] **Step 7: Commit** `test: verify offline startup release behavior`.
- [ ] **Step 8: Build the final release APK locally only after clean analysis and passing tests; verify the APK file and version metadata.**
- [ ] **Step 9: Publish the APK as a GitHub Release asset** in `Olega20/Lerua_Zakup` and provide the direct GitHub download link to the user.

---

## Plan Execution Rules

- The plan is executed one task at a time. The user reviews and accepts each completed task before the next task begins, as required by the project workflow.
- Every task ends with its own commit pushed to GitHub and a verified fetch of changed files. The initial generated scaffold is also committed and pushed before further work.
- Initial Flutter scaffold generation is the sole exception to GitHub-only source editing: the user explicitly permits running `flutter create` on the computer to generate initial files. Commit that complete scaffold immediately and push it to GitHub; do not manually edit the generated source locally.
- After the initial scaffold commit, all source-code changes are made through GitHub; local Windows environment is used only to pull/update the repository, run analysis and tests, build APKs, install builds, and collect logs. Never write or manually edit source code on the computer.
- For every task: author/modify source through GitHub, pull the latest commit to `D:\\src\\Lerua_Zakup`, run the planned tests and analysis locally, read the complete relevant output, fix failures through GitHub, pull again, and repeat until clean. Do not proceed to the next task until the user has reviewed and accepted the current task.
- Final release gate: after clean analysis and passing tests, build the release APK locally, verify the artifact, publish it as a downloadable asset in a GitHub Release for this repository, and give the user the GitHub download URL. Do not commit a generated APK into the source tree unless GitHub Releases are unavailable and the user approves an alternative.
- If a task reveals that an approved requirement is ambiguous or technically unsupported, stop at that task boundary, explain the issue, and request a decision before changing scope.
- No implementation starts until the user approves this plan and chooses an execution method.
