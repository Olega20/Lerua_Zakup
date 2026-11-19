import 'dart:async';

import '../../../core/storage/secure_token_store.dart';
import '../domain/api_check_result.dart';
import '../domain/api_connection_state.dart';
import 'moysklad_api_client.dart';

class MoySkladApiManager {
  MoySkladApiManager({
    required SecureTokenStore _tokenStore,
    required MoySkladApiClient _apiClient,
    required Stream<bool> _internet,
    this.checkInterval = const Duration(minutes: 5),
    DateTime Function()? clock,
    Timer Function(Duration, void Function())? periodicTimer,
  }) : _clock = clock ?? DateTime.now,
       _periodicTimer = periodicTimer ?? _defaultPeriodicTimer;

  final SecureTokenStore _tokenStore;
  final MoySkladApiClient _apiClient;
  final Stream<bool> _internet;
  final Duration checkInterval;
  final DateTime Function() _clock;
  final Timer Function(Duration, void Function()) _periodicTimer;

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
    _internetSubscription = _internet.distinct().listen(_handleInternet);
    _updateTimer();
  }

  void _handleInternet(bool online) {
    if (_online == online) return;
    _online = online;
    _generation++;
    if (!online) {
      _retryNotBefore = null;
      _setState(ApiConnectionState.offline);
    } else {
      _setState(ApiConnectionState.unavailable);
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
    _retryNotBefore = null;
    if (_online) {
      _setState(ApiConnectionState.unavailable);
      await checkNow();
    }
  }

  void onTokenDeleted() {
    _generation++;
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
    try {
      final token = await _tokenStore.readToken();
      if (!_isCurrent(generation)) return;
      if (token == null || token.trim().isEmpty) {
        _lastCheckAt = _clock();
        _setState(ApiConnectionState.unavailable);
        return;
      }

      final result = await _apiClient.checkConnection(token);
      if (!_isCurrent(generation)) return;
      _lastCheckAt = _clock();
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
    } catch (_) {
      if (_isCurrent(generation)) {
        _lastCheckAt = _clock();
        _setState(ApiConnectionState.unavailable);
      }
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
