import 'dart:async';

import '../../../core/storage/secure_token_store.dart';
import '../../../core/diagnostics/emergency_diagnostic_sink.dart';
import '../domain/api_task.dart';
import '../domain/api_task_execution_exception.dart';
import 'api_task_repository.dart';
import 'moysklad_api_client.dart';

/// Single-flight FIFO executor. Only idempotent GET requests are supported
/// by this first dispatcher; ambiguous writes are never retried.
class ApiTaskDispatcher {
  ApiTaskDispatcher({
    required this.repository,
    required this.apiClient,
    required this.tokenStore,
    required this.internet,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final ApiTaskRepository repository;
  final MoySkladApiClient apiClient;
  final SecureTokenStore tokenStore;
  final Stream<bool> internet;
  final DateTime Function() _clock;

  StreamSubscription<bool>? _subscription;
  Timer? _pumpTimer;
  Timer? _watchdogTimer;
  Timer? _rateLimitTimer;
  bool _online = false;
  bool _started = false;
  bool _pumping = false;
  bool _disposed = false;
  int _tokenGeneration = 0;
  ApiTaskClaim? _activeClaim;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    await repository.recoverAfterProcessRestart(clock: _clock);
    _subscription = internet.distinct().listen(_onInternet);
    _pumpTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => unawaited(pump()),
    );
    _watchdogTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      try {
        await repository.markStaleRunningUncertain(clock: _clock);
      } catch (error) {
        await EmergencyDiagnosticSink.record(
          'ApiTaskDispatcher.watchdog',
          error,
        );
      }
    });
  }

  void _onInternet(bool online) {
    _online = online;
    if (!online) {
      _rateLimitTimer?.cancel();
      unawaited(
        repository.pauseAll(
          paused: true,
          reason: 'Нет интернет-соединения',
          clock: _clock,
        ),
      );
    } else {
      _rateLimitTimer?.cancel();
      unawaited(
        repository.resumeGlobalIfReason(
          'Нет интернет-соединения',
          clock: _clock,
        ),
      );
      unawaited(pump());
    }
  }

  Future<void> enqueueGet({
    required String uid,
    required String type,
    required String logicalQueue,
    required String path,
    Map<String, String> query = const {},
    Iterable<int> journalEntryIds = const [],
  }) async {
    await repository.enqueue(
      uid: uid,
      type: type,
      logicalQueue: logicalQueue,
      request: {'method': 'GET', 'path': path, 'query': query},
      journalEntryIds: journalEntryIds,
      clock: _clock,
    );
    unawaited(pump());
  }

  Future<void> pump() async {
    if (_disposed || !_online || _pumping) return;
    _pumping = true;
    try {
      final tokenGeneration = _tokenGeneration;
      final token = await tokenStore.readToken();
      if (tokenGeneration != _tokenGeneration) return;
      if (token == null || token.trim().isEmpty) {
        await repository.pauseAll(
          paused: true,
          reason: 'Не сохранён Access Token',
          clock: _clock,
        );
        await repository.cancelPending(clock: _clock);
        return;
      }
      while (!_disposed && _online) {
        final claim = await repository.claimNext(clock: _clock);
        if (claim == null) break;
        _activeClaim = claim;
        final requestGeneration = tokenGeneration;
        final request = claim.task.request;
        final path = request['path'];
        if (request['method'] != 'GET' ||
            path is! String ||
            !path.startsWith('/')) {
          await repository.finishAttempt(
            taskId: claim.task.id,
            attemptNumber: claim.attemptNumber,
            status: ApiTaskStatus.failed,
            safeErrorCode: 'UNSUPPORTED_REQUEST',
            safeErrorMessage:
                'Менеджер API получил неподдерживаемый тип запроса.',
            clock: _clock,
          );
          _activeClaim = null;
          continue;
        }
        final rawQuery = request['query'];
        final query = rawQuery is Map
            ? rawQuery.map(
                (key, value) => MapEntry(key.toString(), value.toString()),
              )
            : <String, String>{};
        final result = await apiClient.getResource(token, path, query: query);
        if (requestGeneration != _tokenGeneration) {
          await repository.finishAttempt(
            taskId: claim.task.id,
            attemptNumber: claim.attemptNumber,
            status: ApiTaskStatus.uncertain,
            safeErrorCode: 'TOKEN_REMOVED_IN_FLIGHT',
            safeErrorMessage: 'Access Token удалён во время запроса; результат не подтверждён.',
            clock: _clock,
          );
          _activeClaim = null;
          break;
        }
        if (result.isSuccess) {
          await repository.finishAttempt(
            taskId: claim.task.id,
            attemptNumber: claim.attemptNumber,
            status: ApiTaskStatus.succeeded,
            response: result.data,
            httpStatusCode: result.statusCode,
            clock: _clock,
          );
          _activeClaim = null;
          continue;
        }
        if (result.isRetryable) {
          final delay =
              result.retryAfter ??
              Duration(seconds: 2 * (1 << (claim.attemptNumber - 1)));
          await repository.finishAttempt(
            taskId: claim.task.id,
            attemptNumber: claim.attemptNumber,
            status: ApiTaskStatus.retryWait,
            response: result.data,
            httpStatusCode: result.statusCode,
            safeErrorCode: result.errorCode ?? 'TEMPORARY_API_ERROR',
            safeErrorMessage: _messageFor(result.statusCode),
            nextAttemptAt: _clock().add(delay),
            clock: _clock,
          );
          _activeClaim = null;
          if (result.statusCode >= 500 || result.statusCode == 429) {
            final pauseReason =
                'МойСклад временно недоступен (HTTP ${result.statusCode})';
            await repository.pauseAll(
              paused: true,
              reason: pauseReason,
              clock: _clock,
            );
            _rateLimitTimer?.cancel();
            _rateLimitTimer = Timer(delay, () {
              unawaited(
                repository
                    .resumeGlobalIfReason(pauseReason, clock: _clock)
                    .then((_) => pump()),
              );
            });
            break;
          }
        } else {
          await repository.finishAttempt(
            taskId: claim.task.id,
            attemptNumber: claim.attemptNumber,
            status: ApiTaskStatus.failed,
            response: result.data,
            httpStatusCode: result.statusCode,
            safeErrorCode: result.errorCode ?? 'API_REJECTED',
            safeErrorMessage: _messageFor(result.statusCode),
            clock: _clock,
          );
          _activeClaim = null;
          if (result.statusCode == 401 || result.statusCode == 403) {
            await repository.pauseAll(
              paused: true,
              reason: 'МойСклад отклонил доступ',
              clock: _clock,
            );
            break;
          }
        }
      }
    } catch (error) {
      await EmergencyDiagnosticSink.record('ApiTaskDispatcher.pump', error);
    } finally {
      _pumping = false;
    }
  }

  String _messageFor(int status) => switch (status) {
    401 => 'МойСклад не принял Access Token.',
    403 => 'У Access Token недостаточно прав.',
    404 => 'Запрошенный ресурс в МойСклад не найден.',
    429 => 'МойСклад ограничил частоту запросов.',
    >= 500 => 'Сервис МойСклад временно недоступен.',
    408 => 'Истекло время ожидания ответа МойСклад.',
    _ => 'МойСклад отклонил запрос (HTTP $status).',
  };

  Future<Map<String, Object?>> requestGet({
    required String uid,
    required String type,
    required String logicalQueue,
    required String path,
    Map<String, String> query = const {},
    Duration timeout = const Duration(minutes: 3),
  }) async {
    await enqueueGet(
      uid: uid,
      type: type,
      logicalQueue: logicalQueue,
      path: path,
      query: query,
    );
    final deadline = _clock().add(timeout);
    while (_clock().isBefore(deadline) && !_disposed) {
      final tasks = await repository.listTasks(limit: 500);
      ApiTask? task;
      for (final candidate in tasks) {
        if (candidate.uid == uid) {
          task = candidate;
          break;
        }
      }
      if (task != null) {
        if (task.status == ApiTaskStatus.succeeded) {
          return task.response ?? <String, Object?>{};
        }
        if (task.status == ApiTaskStatus.failed ||
            task.status == ApiTaskStatus.uncertain ||
            task.status == ApiTaskStatus.cancelled) {
          final history = await repository.taskHistory(task.id);
          final attempts = history['attempts'] ?? const [];
          final lastAttempt = attempts.isEmpty ? null : attempts.last;
          throw ApiTaskExecutionException(
            task.status,
            task.response,
            taskId: task.id,
            attemptNumber: lastAttempt?['attempt_number'] as int?,
            httpStatusCode: lastAttempt?['http_status_code'] as int?,
            safeErrorCode: lastAttempt?['safe_error_code'] as String?,
            safeErrorMessage: lastAttempt?['safe_error_message'] as String?,
          );
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    throw TimeoutException('API task did not complete in time');
  }

  Future<void> retryFailed(int taskId) async {
    await repository.retryFailed(taskId, clock: _clock);
    await pump();
  }

  Future<void> resolveUncertain(
    int taskId, {
    required bool confirmedSucceeded,
  }) => repository.resolveUncertain(
    taskId,
    confirmedSucceeded: confirmedSucceeded,
    clock: _clock,
  );

  Future<void> setGlobalPaused(bool paused) => repository.pauseAll(
    paused: paused,
    reason: paused ? 'Пауза пользователя' : null,
    clock: _clock,
  );

  Future<void> confirmResumeAfterRestart() async {
    await repository.confirmResumeAfterRestart(clock: _clock);
    await pump();
  }

  Future<int> cancelPending({String? logicalQueue}) =>
      repository.cancelPending(logicalQueue: logicalQueue, clock: _clock);

  Future<int> deleteAllTasks() async {
    final wasPaused = await repository.isQueuePaused();
    await repository.pauseAll(
      paused: true,
      reason: 'Очистка Менеджера API',
      clock: _clock,
    );
    while (_pumping && !_disposed) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    final deleted = await repository.deleteAllTasks();
    if (!wasPaused) {
      await repository.pauseAll(paused: false, clock: _clock);
      if (_online) unawaited(pump());
    }
    return deleted;
  }

  Future<void> onTokenSaved() async {
    if (_online) {
      await repository.resumeGlobalIfReason(
        'Не сохранён Access Token',
        clock: _clock,
      );
      await repository.resumeGlobalIfReason(
        'Access Token удалён',
        clock: _clock,
      );
      await repository.resumeGlobalIfReason(
        'МойСклад отклонил доступ',
        clock: _clock,
      );
      await pump();
    }
  }

  Future<void> onTokenDeleted() async {
    _tokenGeneration++;
    final active = _activeClaim;
    if (active != null) {
      await repository.finishAttempt(
        taskId: active.task.id,
        attemptNumber: active.attemptNumber,
        status: ApiTaskStatus.uncertain,
        safeErrorCode: 'TOKEN_REMOVED_IN_FLIGHT',
        safeErrorMessage:
            'Access Token удалён во время запроса; результат не подтверждён.',
        clock: _clock,
      );
      _activeClaim = null;
    }
    await repository.pauseAll(
      paused: true,
      reason: 'Access Token удалён',
      clock: _clock,
    );
    await repository.cancelPending(clock: _clock);
  }

  Future<List<ApiTask>> listTasks({
    String? logicalQueue,
    Set<ApiTaskStatus>? statuses,
  }) => repository.listTasks(logicalQueue: logicalQueue, statuses: statuses);

  Future<bool> isGloballyPaused() => repository.isQueuePaused();

  Future<bool> isQueuePaused(String queue) => repository.isQueuePaused(queue);

  Future<void> setQueuePaused(String queue, bool paused) =>
      repository.pauseQueue(
        queue,
        paused: paused,
        reason: paused ? 'Пауза пользователя' : null,
        clock: _clock,
      );

  Future<Map<String, List<Map<String, Object?>>>> taskHistory(int taskId) =>
      repository.taskHistory(taskId);

  Future<void> suspendForDatabaseMaintenance() async {
    await repository.pauseAll(
      paused: true,
      reason: 'Обслуживание базы данных',
      clock: _clock,
    );
    _pumpTimer?.cancel();
    _watchdogTimer?.cancel();
    _rateLimitTimer?.cancel();
    await _subscription?.cancel();
    _subscription = null;
    _online = false;
  }

  Future<void> resumeAfterDatabaseMaintenance() async {
    if (_disposed) return;
    await repository.recoverAfterProcessRestart(clock: _clock);
    _subscription = internet.distinct().listen(_onInternet);
    _pumpTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => unawaited(pump()),
    );
    _watchdogTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      try {
        await repository.markStaleRunningUncertain(clock: _clock);
      } catch (error) {
        await EmergencyDiagnosticSink.record(
          'ApiTaskDispatcher.watchdog',
          error,
        );
      }
    });
  }

  Future<void> dispose() async {
    _disposed = true;
    _pumpTimer?.cancel();
    _watchdogTimer?.cancel();
    _rateLimitTimer?.cancel();
    await _subscription?.cancel();
  }
}
