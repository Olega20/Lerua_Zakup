import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../core/feedback/snackbar_service.dart';
import '../core/storage/preferences_store.dart';
import '../core/storage/app_database.dart';
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
import '../features/connectivity/data/api_task_repository.dart';
import '../features/connectivity/data/api_task_dispatcher.dart';
import '../features/references/data/reference_data_repository.dart';
import '../features/references/presentation/reference_screens.dart';
import '../features/warehouse_journal/data/warehouse_journal_repository.dart';
import '../features/backup/data/backup_service.dart';
import '../core/diagnostics/emergency_diagnostic_sink.dart';
import '../features/connectivity/data/platform_connectivity_source.dart';
import '../features/connectivity/domain/api_connection_state.dart';
import 'app_theme.dart';

class LeruaZakupApp extends StatefulWidget {
  const LeruaZakupApp({
    super.key,
    this.settingsRepository,
    this.warehouseLogRepository,
    this.appVersionOverride,
    this.onExitRequested,
    this.startApiTaskDispatcher = false,
  });

  final SettingsRepository? settingsRepository;
  final WarehouseLogRepository? warehouseLogRepository;
  final String? appVersionOverride;
  final VoidCallback? onExitRequested;
  final bool startApiTaskDispatcher;

  @override
  State<LeruaZakupApp> createState() => _LeruaZakupAppState();
}

class _LeruaZakupAppState extends State<LeruaZakupApp>
    with WidgetsBindingObserver {
  final AppRouter _router = AppRouter();
  final SnackbarService _snackbarService = SnackbarService();
  late final PlatformConnectivitySource _connectivitySource =
      PlatformConnectivitySource();
  late final FlutterSecureTokenStore _tokenStore = FlutterSecureTokenStore();
  late final Stream<bool> _internetStream = _connectivitySource.hasInternet
      .asBroadcastStream();
  late final MoySkladApiManager _apiManager = MoySkladApiManager(
    tokenStore: _tokenStore,
    apiClient: MoySkladApiClient(),
    internet: _internetStream,
    onEvent: _warehouseLogRepository.append,
  );
  late final Stream<ApiConnectionState> _connectivityStatuses =
      _apiManager.states;
  late final ApiTaskRepository _apiTaskRepository = ApiTaskRepository(
    database: _appDatabase,
  );
  late final ApiTaskDispatcher _apiTaskDispatcher = ApiTaskDispatcher(
    repository: _apiTaskRepository,
    apiClient: MoySkladApiClient(),
    tokenStore: _tokenStore,
    internet: _internetStream,
  );
  late final ReferenceDataRepository _referenceDataRepository =
      ReferenceDataRepository(
        database: _appDatabase,
        api: _apiTaskDispatcher,
        directApiClient: MoySkladApiClient(),
        tokenStore: _tokenStore,
        warehouseLog: _warehouseLogRepository,
      );
  late final WarehouseJournalRepository _warehouseJournalRepository =
      WarehouseJournalRepository(
        database: _appDatabase,
        warehouseLog: _warehouseLogRepository,
      );
  late final BackupService _backupService = BackupService(
    database: _appDatabase,
    warehouseLog: _warehouseLogRepository,
  );
  late final AppDatabase _appDatabase = AppDatabase();
  late final WarehouseLogRepository _warehouseLogRepository =
      widget.warehouseLogRepository ??
      WarehouseLogRepository(
        storage: SqfliteWarehouseLogStorage(appDatabase: _appDatabase),
      );
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
  Future<void>? _referenceSyncFuture;
  StreamSubscription<bool>? _referenceSyncSubscription;

  @override
  void initState() {
    super.initState();
    _lifecycle.initialize();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _checkStorageCapacity();
    });
    unawaited(_apiManager.start());
    if (widget.startApiTaskDispatcher) {
      unawaited(_startBackgroundServices());
    }
    _initializeNotifications();
    _restoreSettings();
    if (widget.appVersionOverride != null) {
      _appVersion = widget.appVersionOverride!;
    } else {
      _loadVersion();
    }
  }

  Future<void> _startBackgroundServices() async {
    try {
      await _apiTaskDispatcher.start();
      _referenceSyncSubscription = _internetStream.listen((online) {
        if (online) unawaited(_syncReferencesOnStartup());
      });
      await _backupService.ensureDailyBackup();
      await Future<void>.delayed(const Duration(seconds: 2));
      await _syncReferencesOnStartup();
    } catch (error) {
      await EmergencyDiagnosticSink.record('App.backgroundStartup', error);
    }
  }

  Future<void> _syncReferencesOnStartup() {
    final active = _referenceSyncFuture;
    if (active != null) return active;
    final future = _runReferenceSync();
    _referenceSyncFuture = future;
    return future.whenComplete(() => _referenceSyncFuture = null);
  }

  Future<void> _runReferenceSync() async {
    try {
      final token = await _tokenStore.readToken();
      if (token == null || token.trim().isEmpty || !_apiManager.isOnline) {
        return;
      }
      if (await _apiTaskRepository.requiresResumeConfirmation()) return;
      await _referenceDataRepository.syncProducts();
      await _referenceDataRepository.syncWarehouses();
      await _referenceDataRepository.syncOrganizations();
    } catch (error) {
      await EmergencyDiagnosticSink.record('App.referenceStartupSync', error);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _apiManager.setForeground(state == AppLifecycleState.resumed);
    if (state == AppLifecycleState.resumed) {
      _checkStorageCapacity();
    }
  }

  Future<void> _handleTokenSaved() async {
    await _apiManager.onTokenSaved();
    if (widget.startApiTaskDispatcher) {
      await _apiTaskDispatcher.onTokenSaved();
    }
    if (!mounted || !_apiManager.isOnline) return;
    if (_apiManager.currentState != ApiConnectionState.connected) {
      _snackbarService.showGlobal(
        'Не удалось подтвердить подключение к МойСклад. Подробности в Журнале склада',
      );
    } else if (widget.startApiTaskDispatcher) {
      unawaited(_syncReferencesOnStartup());
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
    unawaited(_referenceSyncSubscription?.cancel());
    unawaited(_apiManager.dispose());
    unawaited(_apiTaskDispatcher.dispose());
    unawaited(_appDatabase.close());
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
            onOpenOtherActions: () {
              final deps = _AppDependencies.of(context);
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => OtherActionsScreen(
                    repository: deps.referenceDataRepository,
                    api: deps.apiTaskDispatcher,
                    journal: deps.warehouseJournalRepository,
                    backupService: deps.backupService,
                    warehouseLogRepository: deps.warehouseLogRepository,
                    onResumeConfirmed: _syncReferencesOnStartup,
                  ),
                ),
              );
            },
            onShowPlaceholder: (message) =>
                _snackbarService.show(context, message),
          ),
        ),
      ),
    ),
    builder: (context, child) => _AppDependencies(
      repository: _settingsRepository,
      warehouseLogRepository: _warehouseLogRepository,
      apiTaskDispatcher: _apiTaskDispatcher,
      referenceDataRepository: _referenceDataRepository,
      warehouseJournalRepository: _warehouseJournalRepository,
      backupService: _backupService,
      appVersion: _appVersion,
      onThemeChanged: (mode) {
        if (mounted) setState(() => _themeMode = mode);
      },
      onSeedColorChanged: (color) {
        if (mounted) setState(() => _seedColor = color);
      },
      onTokenSaved: () => unawaited(_handleTokenSaved()),
      onTokenDeleted: () {
        _apiManager.onTokenDeleted();
        unawaited(_apiTaskDispatcher.onTokenDeleted());
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
    required this.warehouseLogRepository,
    required this.apiTaskDispatcher,
    required this.referenceDataRepository,
    required this.warehouseJournalRepository,
    required this.backupService,
    required this.appVersion,
    required this.onThemeChanged,
    required this.onSeedColorChanged,
    required this.onTokenSaved,
    required this.onTokenDeleted,
    required super.child,
  });

  final SettingsRepository repository;
  final WarehouseLogRepository warehouseLogRepository;
  final ApiTaskDispatcher apiTaskDispatcher;
  final ReferenceDataRepository referenceDataRepository;
  final WarehouseJournalRepository warehouseJournalRepository;
  final BackupService backupService;
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
