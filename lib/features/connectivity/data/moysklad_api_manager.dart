import 'dart:async';

import '../../../core/storage/secure_token_store.dart';
import '../domain/api_check_result.dart';
import '../domain/api_connection_state.dart';
import '../../warehouse_log/domain/warehouse_log_entry.dart';
import '../../warehouse_log/domain/warehouse_error_classifier.dart';
import 'moysklad_api_client.dart';

class MoySkladApiManager {
  MoySkladApiManager({
    required this.tokenStore,
    required this.apiClient,
    required this.internet,
    this.checkInterval = const Duration(minutes: 5),
    DateTime Function()? clock,
    Timer Function(Duration, void Function())? periodicTimer,
    this.onEvent,
  }) : _clock = clock ?? DateTime.now,
       _periodicTimer = periodicTimer ?? _defaultPeriodicTimer;

  final SecureTokenStore tokenStore;
  final MoySkladApiClient apiClient;
  final Stream<bool> internet;
  final Duration checkInterval;
  final DateTime Function() _clock;
  final Timer Function(Duration, void Function()) _periodicTimer;
  final Future<void> Function(WarehouseLogEntry entry)? onEvent;

  final StreamController<ApiConnectionState> _states =
      StreamController<ApiConnectionState>.broadcast();
  StreamSubscription<bool>? _internetSubscription;
  Timer? _timer;
  Future<void>? _activeCheck;
  ApiConnectionState _state = ApiConnectionState.offline;
  DateTime? _lastCheckAt;
  int _generation = 0;
  bool _online = false;
  bool _foreground = true;
  bool _started = false;
  bool _checkAgain = false;
  DateTime? _retryNotBefore;

  static Timer _defaultPeriodicTimer(
    Duration duration,
    void Function() callback,
  ) => Timer.periodic(duration, (_) => callback());

  ApiConnectionState get currentState => _state;

  bool get isOnline => _online;

  Stream<ApiConnectionState> get states =>
      Stream<ApiConnectionState>.multi((controller) {
        controller.add(_state);
        final subscription = _states.stream.listen(
          controller.add,
          onError: controller.addError,
          onDone: controller.close,
        );
        controller.onCancel = subscription.cancel;
      });

  Future<void> start() async {
    if (_started) return;
    _started = true;
    _internetSubscription = internet.distinct().listen(_handleInternet);
    _updateTimer();
  }

  void _handleInternet(bool online) {
    if (_online == online) return;
    _online = online;
    _generation++;
    if (!online) {
      _setState(ApiConnectionState.offline);
      unawaited(
        _recordEvent(
          WarehouseLogLevel.warning,
          WarehouseLogEventType.internetLost,
          'Подтверждённое интернет-соединение потеряно',
        ),
      );
    } else {
      _setState(ApiConnectionState.unavailable);
      unawaited(
        _recordEvent(
          WarehouseLogLevel.info,
          WarehouseLogEventType.internetRestored,
          'Подтверждённое интернет-соединение восстановлено',
        ),
      );
      unawaited(checkNow());
    }
    _updateTimer();
  }

  void _setState(ApiConnectionState state) {
    if (_state == state) return;
    _state = state;
    if (!_states.isClosed) _states.add(state);
  }

  Future<void> onTokenSaved() async {
    _generation++;
    await _recordEvent(
      WarehouseLogLevel.info,
      WarehouseLogEventType.tokenSaved,
      'Access Token сохранён',
    );
    if (_online) {
      _setState(ApiConnectionState.unavailable);
      await checkNow();
    }
  }

  void onTokenDeleted() {
    _generation++;
    unawaited(
      _recordEvent(
        WarehouseLogLevel.info,
        WarehouseLogEventType.tokenDeleted,
        'Access Token удалён',
      ),
    );
    _retryNotBefore = null;
    _setState(
      _online ? ApiConnectionState.unavailable : ApiConnectionState.offline,
    );
  }

  void setForeground(bool foreground) {
    if (_foreground == foreground) return;
    _foreground = foreground;
    if (!foreground) {
      _generation++;
      if (_online) _setState(ApiConnectionState.unavailable);
    }
    _updateTimer();
    if (foreground &&
        _online &&
        (_lastCheckAt == null ||
            _clock().difference(_lastCheckAt!) >= checkInterval)) {
      unawaited(checkNow());
    }
  }

  void _updateTimer() {
    _timer?.cancel();
    _timer = null;
    if (_started && _foreground && _online) {
      _timer = _periodicTimer(checkInterval, () {
        if (_online && _foreground) unawaited(checkNow());
      });
    }
  }

  Future<void> checkNow() {
    if (!_online || !_foreground) return Future<void>.value();
    final active = _activeCheck;
    if (active != null) {
      _checkAgain = true;
      return active;
    }
    final future = _runChecks();
    _activeCheck = future;
    return future.whenComplete(() {
      if (identical(_activeCheck, future)) _activeCheck = null;
    });
  }

  Future<void> _runChecks() async {
    do {
      _checkAgain = false;
      await _performSingleCheck();
    } while (_checkAgain && _online && _foreground);
  }

  Future<void> _performSingleCheck() async {
    if (!_online || !_foreground) return;
    final retryAt = _retryNotBefore;
    if (retryAt != null && _clock().isBefore(retryAt)) return;

    final generation = _generation;
    _setState(ApiConnectionState.checking);
    await _recordEvent(
      WarehouseLogLevel.info,
      WarehouseLogEventType.checkStarted,
      'Проверка доступности API запущена',
    );
    if (!_isCurrent(generation)) return;
    try {
      final token = await tokenStore.readToken();
      if (!_isCurrent(generation)) return;
      if (token == null || token.trim().isEmpty) {
        _lastCheckAt = _clock();
        await _recordEvent(
          WarehouseLogLevel.warning,
          WarehouseLogEventType.missingToken,
          'Access Token не сохранён',
        );
        _setState(ApiConnectionState.unavailable);
        return;
      }

      final result = await apiClient.checkConnection(token);
      if (!_isCurrent(generation)) return;
      _lastCheckAt = _clock();
      final event = _eventForResult(result);
      await _recordEvent(
        event.$1,
        event.$2,
        event.$3,
        httpStatusCode: result.httpStatusCode,
      );
      if (!_isCurrent(generation)) return;
      if (result.status == ApiCheckStatus.rateLimited) {
        _retryNotBefore = _clock().add(result.retryAfter ?? checkInterval);
        _setState(ApiConnectionState.unavailable);
        return;
      }
      _retryNotBefore = null;
      _setState(
        result.isConnected
            ? ApiConnectionState.connected
            : ApiConnectionState.unavailable,
      );
    } catch (error) {
      if (_isCurrent(generation)) {
        _lastCheckAt = _clock();
        await _recordFailure(error);
        _setState(ApiConnectionState.unavailable);
      }
    }
  }

  (WarehouseLogLevel, WarehouseLogEventType, String) _eventForResult(
    ApiCheckResult result,
  ) => switch (result.status) {
    ApiCheckStatus.connected => (
      WarehouseLogLevel.info,
      WarehouseLogEventType.checkSucceeded,
      'МойСклад ответил успешно',
    ),
    ApiCheckStatus.missingToken => (
      WarehouseLogLevel.warning,
      WarehouseLogEventType.missingToken,
      'Access Token не сохранён',
    ),
    ApiCheckStatus.unauthorized => (
      WarehouseLogLevel.warning,
      WarehouseLogEventType.unauthorized,
      'API отклонил Access Token',
    ),
    ApiCheckStatus.forbidden => (
      WarehouseLogLevel.warning,
      WarehouseLogEventType.forbidden,
      'У токена нет прав на проверку контекста',
    ),
    ApiCheckStatus.rateLimited => (
      WarehouseLogLevel.warning,
      WarehouseLogEventType.rateLimited,
      'API ограничил частоту запросов',
    ),
    ApiCheckStatus.timeout => (
      WarehouseLogLevel.error,
      WarehouseLogEventType.timeout,
      'API не ответил за отведённое время',
    ),
    ApiCheckStatus.invalidResponse => (
      WarehouseLogLevel.error,
      WarehouseLogEventType.invalidResponse,
      'API вернул некорректный JSON-ответ',
    ),
    ApiCheckStatus.unavailable => (
      WarehouseLogLevel.error,
      WarehouseLogEventType.apiUnavailable,
      'Не удалось получить успешный ответ API',
    ),
  };

  Future<void> _recordFailure(Object error) async {
    final sink = onEvent;
    if (sink == null) return;
    final diagnostic = const WarehouseErrorClassifier().describe(error);
    try {
      await sink(WarehouseLogEntry(
        timestamp: _clock(),
        level: WarehouseLogLevel.error,
        type: diagnostic.type,
        description: diagnostic.message,
        component: 'MoySklad API Manager',
        errorCode: diagnostic.code,
        recommendedAction: diagnostic.recommendedAction,
        technicalDetails: diagnostic.technicalDetails,
      ));
    } catch (_) {
      // A failed diagnostic write must not hide the original connectivity error.
    }
  }

  Future<void> _recordEvent(
    WarehouseLogLevel level,
    WarehouseLogEventType type,
    String description, {
    int? httpStatusCode,
  }) async {
    final sink = onEvent;
    if (sink == null) return;
    try {
      await sink(
        WarehouseLogEntry(
          timestamp: _clock(),
          level: level,
          type: type,
          description: description,
          httpStatusCode: httpStatusCode,
        ),
      );
    } catch (_) {
      // Diagnostics must never interrupt connectivity checks or app startup.
    }
  }

  bool _isCurrent(int generation) =>
      generation == _generation && _online && _foreground;

  Future<void> dispose() async {
    _generation++;
    _timer?.cancel();
    _timer = null;
    await _internetSubscription?.cancel();
    await _states.close();
    _started = false;
  }
}
