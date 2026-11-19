import 'dart:async';

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
import '../features/warehouse_log/data/warehouse_log_repository.dart';
import '../features/warehouse_log/data/warehouse_log_storage.dart';
import 'app_router.dart';
import 'app_lifecycle.dart';
import '../core/notifications/notification_service.dart';
import '../core/platform/storage_capacity_service.dart';
import '../core/platform/storage_warning_controller.dart';
import '../features/connectivity/data/moysklad_api_client.dart';
import '../features/connectivity/data/moysklad_api_manager.dart';
import '../features/connectivity/data/platform_connectivity_source.dart';
import '../features/connectivity/domain/api_connection_state.dart';
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
  late final PlatformConnectivitySource _connectivitySource =
      PlatformConnectivitySource();
  late final MoySkladApiManager _apiManager = MoySkladApiManager(
    tokenStore: FlutterSecureTokenStore(),
    apiClient: MoySkladApiClient(),
    internet: _connectivitySource.hasInternet.asBroadcastStream(),
  );
  late final Stream<ApiConnectionState> _connectivityStatuses =
      _apiManager.states;
  late final WarehouseLogRepository _warehouseLogRepository =
      WarehouseLogRepository(storage: SqfliteWarehouseLogStorage());
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
  Color _seedColor = AppTheme.defaultSeedColor;
  String _appVersion = '1.0.0+1';

  @override
  void initState() {
    super.initState();
    _lifecycle.initialize();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _checkStorageCapacity();
    });
    unawaited(_apiManager.start());
    _initializeNotifications();
    _restoreSettings();
    if (widget.appVersionOverride != null) {
      _appVersion = widget.appVersionOverride!;
    } else {
      _loadVersion();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _apiManager.setForeground(state == AppLifecycleState.resumed);
    if (state == AppLifecycleState.resumed) {
      _checkStorageCapacity();
    }
  }

  Future<void> _checkStorageCapacity() async {
    try {
      await _storageWarningController.check();
    } catch (_) {
      // Storage warnings are best-effort and must never interrupt app use.
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
    unawaited(_apiManager.dispose());
    super.dispose();
  }

  Future<void> _restoreSettings() async {
    final mode = await _settingsRepository.loadTheme();
    final seedColor = await _settingsRepository.loadSeedColor();
    if (mounted) {
      setState(() {
        _themeMode = mode;
        _seedColor = seedColor;
      });
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
        onSeedColorChanged: dependencies.onSeedColorChanged,
        onTokenSaved: dependencies.onTokenSaved,
        onTokenDeleted: dependencies.onTokenDeleted,
        warehouseLogRepository: dependencies.warehouseLogRepository,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Lerua Zakup',
    restorationScopeId: 'lerua_zakup_app',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light(seedColor: _seedColor),
    darkTheme: AppTheme.dark(seedColor: _seedColor),
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
      warehouseLogRepository: _warehouseLogRepository,
      appVersion: _appVersion,
      onThemeChanged: (mode) {
        if (mounted) setState(() => _themeMode = mode);
      },
      onSeedColorChanged: (color) {
        if (mounted) setState(() => _seedColor = color);
      },
      onTokenSaved: () => unawaited(_apiManager.onTokenSaved()),
      onTokenDeleted: _apiManager.onTokenDeleted,
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
    required this.warehouseLogRepository,
    required this.appVersion,
    required this.onThemeChanged,
    required this.onSeedColorChanged,
    required this.onTokenSaved,
    required this.onTokenDeleted,
    required super.child,
  });

  final SettingsRepository repository;
  final WarehouseLogRepository warehouseLogRepository;
  final String appVersion;
  final ValueChanged<ThemeMode> onThemeChanged;
  final ValueChanged<Color> onSeedColorChanged;
  final VoidCallback onTokenSaved;
  final VoidCallback onTokenDeleted;

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
