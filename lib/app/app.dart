import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../core/feedback/snackbar_service.dart';
import '../core/storage/preferences_store.dart';
import '../core/storage/secure_token_store.dart';
import '../features/calendar/presentation/full_calendar_screen.dart';
import '../features/home/presentation/home_screen.dart';
import '../features/settings/data/settings_repository.dart';
import '../features/settings/presentation/settings_screen.dart';
import 'app_router.dart';
import 'app_lifecycle.dart';
import '../core/notifications/notification_service.dart';
import '../core/platform/storage_capacity_service.dart';
import '../core/platform/storage_warning_controller.dart';
import '../features/connectivity/data/connectivity_monitor.dart';
import '../features/connectivity/data/platform_connectivity_source.dart';
import '../features/connectivity/domain/connectivity_status.dart';
import 'app_theme.dart';

class LeruaZakupApp extends StatefulWidget {
  const LeruaZakupApp({
    super.key,
    this.settingsRepository,
    this.appVersionOverride,
    this.onExitRequested,
  });

  final SettingsRepository? settingsRepository;
  final String? appVersionOverride;
  final VoidCallback? onExitRequested;

  @override
  State<LeruaZakupApp> createState() => _LeruaZakupAppState();
}

class _LeruaZakupAppState extends State<LeruaZakupApp>
    with WidgetsBindingObserver {
  final AppRouter _router = AppRouter();
  final SnackbarService _snackbarService = SnackbarService();
  late final Stream<ConnectivityStatus> _connectivityStatuses =
      ConnectivityMonitor(source: PlatformConnectivitySource()).statuses
          .asBroadcastStream();
  late final StorageWarningController _storageWarningController =
      StorageWarningController(
        capacityService: StorageCapacityService(),
        store: SharedPreferencesStorageWarningStore(),
        onWarning: () =>
            _snackbarService.showGlobal('Мало свободного места на устройстве'),
      );
  final HomeBackController _homeBackController = HomeBackController();
  late final AppLifecycleController _lifecycle = AppLifecycleController(
    systemUi: FlutterSystemUiController(),
  );
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
    _lifecycle.initialize();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _storageWarningController.check();
    });
    _initializeNotifications();
    _restoreTheme();
    if (widget.appVersionOverride != null) {
      _appVersion = widget.appVersionOverride!;
    } else {
      _loadVersion();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _storageWarningController.check();
    }
  }

  void _exitApp() {
    final callback = widget.onExitRequested;
    if (callback != null) {
      callback();
    } else {
      SystemNavigator.pop();
    }
  }

  Future<void> _handleHomeBack(BuildContext context) async {
    final action = _homeBackController.handleBack(DateTime.now());
    if (action == HomeBackAction.exit) {
      _exitApp();
      return;
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) _exitApp();
        },
        child: AlertDialog(
          title: const Text('Выйти?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                _exitApp();
              },
              child: const Text('Выйти'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _initializeNotifications() async {
    try {
      await NotificationService(
        platform: MethodChannelNotificationPlatform(),
        store: SharedPreferencesNotificationPermissionStore(),
      ).initializeAndRequestPermission();
    } catch (_) {
      // Notification permission is optional; app startup must continue.
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _lifecycle.dispose();
    super.dispose();
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
    Navigator.restorablePush<void>(context, _calendarRoute);
  }

  void _openSettings(BuildContext context) {
    Navigator.restorablePush<void>(context, _settingsRoute);
  }

  static Route<void> _calendarRoute(BuildContext context, Object? arguments) =>
      MaterialPageRoute<void>(
        builder: (_) => FullCalendarScreen(now: DateTime.now()),
      );

  static Route<void> _settingsRoute(BuildContext context, Object? arguments) {
    final dependencies = _AppDependencies.of(context);
    return MaterialPageRoute<void>(
      builder: (_) => SettingsScreen(
        repository: dependencies.repository,
        appVersion: dependencies.appVersion,
        onThemeChanged: dependencies.onThemeChanged,
        onTokenSaved: dependencies.onTokenSaved,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Lerua Zakup',
    restorationScopeId: 'lerua_zakup_app',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    darkTheme: AppTheme.dark,
    themeMode: _themeMode,
    navigatorKey: _router.navigatorKey,
    scaffoldMessengerKey: _snackbarService.messengerKey,
    home: Builder(
      builder: (context) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) _handleHomeBack(context);
        },
        child: Scaffold(
          body: HomeScreen(
            now: DateTime.now(),
            connectivityStatuses: _connectivityStatuses,
            onOpenCalendar: () => _openCalendar(context),
            onOpenSettings: () => _openSettings(context),
            onShowPlaceholder: (message) =>
                _snackbarService.show(context, message),
          ),
        ),
      ),
    ),
    builder: (context, child) => _AppDependencies(
      repository: _settingsRepository,
      appVersion: _appVersion,
      onThemeChanged: (mode) {
        if (mounted) setState(() => _themeMode = mode);
      },
      onTokenSaved: () {
        // API reachability checks are intentionally excluded from this offline release.
      },
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _snackbarService.dismiss(),
        child: child ?? const SizedBox.shrink(),
      ),
    ),
  );
}

class _AppDependencies extends InheritedWidget {
  const _AppDependencies({
    required this.repository,
    required this.appVersion,
    required this.onThemeChanged,
    required this.onTokenSaved,
    required super.child,
  });

  final SettingsRepository repository;
  final String appVersion;
  final ValueChanged<ThemeMode> onThemeChanged;
  final VoidCallback onTokenSaved;

  static _AppDependencies of(BuildContext context) {
    final dependencies = context
        .dependOnInheritedWidgetOfExactType<_AppDependencies>();
    assert(dependencies != null, 'App dependencies are unavailable');
    return dependencies!;
  }

  @override
  bool updateShouldNotify(_AppDependencies oldWidget) =>
      repository != oldWidget.repository || appVersion != oldWidget.appVersion;
}
