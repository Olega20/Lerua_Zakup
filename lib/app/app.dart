import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../core/feedback/snackbar_service.dart';
import '../core/storage/preferences_store.dart';
import '../core/storage/secure_token_store.dart';
import '../features/calendar/presentation/full_calendar_screen.dart';
import '../features/home/presentation/home_screen.dart';
import '../features/settings/data/settings_repository.dart';
import '../features/settings/presentation/settings_screen.dart';
import 'app_router.dart';
import 'app_theme.dart';

class LeruaZakupApp extends StatefulWidget {
  const LeruaZakupApp({
    super.key,
    this.settingsRepository,
    this.appVersionOverride,
  });

  final SettingsRepository? settingsRepository;
  final String? appVersionOverride;

  @override
  State<LeruaZakupApp> createState() => _LeruaZakupAppState();
}

class _LeruaZakupAppState extends State<LeruaZakupApp> {
  final AppRouter _router = AppRouter();
  final SnackbarService _snackbarService = SnackbarService();
  late final SettingsRepository _settingsRepository =
      widget.settingsRepository ??
      SettingsRepository(
        preferencesStore: SharedPreferencesStore(),
        secureTokenStore: FlutterSecureTokenStore(),
      );

  ThemeMode _themeMode = ThemeMode.light;
  String _appVersion = '1.0.0+1';

  @override
  void initState() {
    super.initState();
    _restoreTheme();
    if (widget.appVersionOverride != null) {
      _appVersion = widget.appVersionOverride!;
    } else {
      _loadVersion();
    }
  }

  Future<void> _restoreTheme() async {
    final mode = await _settingsRepository.loadTheme();
    if (mounted) {
      setState(() => _themeMode = mode);
    }
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() => _appVersion = '${info.version}+${info.buildNumber}');
      }
    } catch (_) {
      // Keep the version from pubspec when platform metadata is unavailable.
    }
  }

  void _openCalendar(BuildContext context) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => FullCalendarScreen(now: DateTime.now()),
      ),
    );
  }

  void _openSettings(BuildContext context) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          repository: _settingsRepository,
          appVersion: _appVersion,
          onThemeChanged: (mode) {
            if (mounted) setState(() => _themeMode = mode);
          },
          onTokenSaved: () {
            // Connectivity/API checking is connected in Task 7.
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Lerua Zakup',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    darkTheme: AppTheme.dark,
    themeMode: _themeMode,
    navigatorKey: _router.navigatorKey,
    home: Builder(
      builder: (context) => Scaffold(
        body: HomeScreen(
          now: DateTime.now(),
          onOpenCalendar: () => _openCalendar(context),
          onOpenSettings: () => _openSettings(context),
          onShowPlaceholder: (message) =>
              _snackbarService.show(context, message),
        ),
      ),
    ),
    builder: (context, child) => Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _snackbarService.dismiss(),
      child: child ?? const SizedBox.shrink(),
    ),
  );
}
