import 'dart:convert';

import 'package:sqflite/sqflite.dart' as sqflite;

import '../../../core/storage/app_database.dart';
import '../domain/api_task.dart';

/// Durable task storage for one global FIFO dispatcher and multiple logical queues.
/// Credentials and Authorization headers must never be included in request data.
class ApiTaskRepository {
  ApiTaskRepository({required AppDatabase database}) : _database = database;

  final AppDatabase _database;
  Future<sqflite.Database> get _db => _database.database;

  Future<ApiTask> enqueue({
    required String uid,
    required String type,
    required String logicalQueue,
    required Map<String, Object?> request,
    Iterable<int> journalEntryIds = const [],
    DateTime Function()? clock,
  }) async {
    final now = (clock ?? DateTime.now)().millisecondsSinceEpoch;
    final safeRequest = jsonEncode(_redactMap(request));
    final db = await _db;
    return db.transaction((txn) async {
      final existing = await txn.query('api_tasks',
          where: 'task_uid = ?', whereArgs: [uid], limit: 1);
      if (existing.isNotEmpty) return _fromRow(existing.first);

      final sequenceRows = await txn.rawQuery(
          'SELECT COALESCE(MAX(fifo_sequence), 0) + 1 AS next_sequence FROM api_tasks');
      final sequence = sequenceRows.first['next_sequence'] as int;
      final id = await txn.insert('api_tasks', {
        'task_uid': uid,
        'task_type': type,
        'logical_queue': logicalQueue,
        'status': 'pending',
        'fifo_sequence': sequence,
        'request_json': safeRequest,
        'attempts_count': 0,
        'created_at': now,
        'updated_at': now,
      });
      await txn.insert('api_task_events', {
        'task_id': id,
        'event_type': 'created',
        'to_state': 'pending',
        'message': 'Задача добавлена в очередь',
        'created_at': now,
      });
      for (final journalId in journalEntryIds.toSet()) {
        await txn.insert('journal_api_task_links', {
          'journal_entry_id': journalId,
          'task_id': id,
          'relation_type': 'related',
        });
      }
      return _fromRow((await txn.query('api_tasks',
          where: 'id = ?', whereArgs: [id], limit: 1)).single);
    });
  }

  /// Claims the oldest due task atomically and records its attempt before I/O.
  Future<ApiTaskClaim?> claimNext({
    DateTime Function()? clock,
    int maximumAttempts = 3,
  }) async {
    final now = (clock ?? DateTime.now)().millisecondsSinceEpoch;
    final db = await _db;
    return db.transaction((txn) async {
      final rows = await txn.rawQuery('''
        SELECT t.* FROM api_tasks t
        WHERE t.status IN ('pending', 'retry_wait')
          AND t.attempts_count < ?
          AND (t.next_attempt_at IS NULL OR t.next_attempt_at <= ?)
          AND NOT EXISTS (
            SELECT 1 FROM api_queue_state q
            WHERE q.logical_queue IN (t.logical_queue, '__all__') AND q.is_paused = 1
          )
        ORDER BY t.fifo_sequence ASC LIMIT 1
      ''', [maximumAttempts, now]);
      if (rows.isEmpty) return null;

      final row = rows.first;
      final id = row['id'] as int;
      final oldStatus = row['status'] as String;
      final attempt = (row['attempts_count'] as int) + 1;
      final changed = await txn.update('api_tasks', {
        'status': 'running',
        'attempts_count': attempt,
        'started_at': now,
        'updated_at': now,
        'next_attempt_at': null,
      }, where: 'id = ? AND status = ?', whereArgs: [id, oldStatus]);
      if (changed != 1) return null;

      await txn.insert('api_task_attempts', {
        'task_id': id,
        'attempt_number': attempt,
        'started_at': now,
        'outcome': 'running',
      });
      await txn.insert('api_task_events', {
        'task_id': id,
        'event_type': 'attempt_started',
        'from_state': oldStatus,
        'to_state': 'running',
        'message': 'Начата попытка $attempt',
        'created_at': now,
      });
      final claimed = (await txn.query('api_tasks',
          where: 'id = ?', whereArgs: [id], limit: 1)).single;
      return ApiTaskClaim(task: _fromRow(claimed), attemptNumber: attempt);
    });
  }

  Future<void> finishAttempt({
    required int taskId,
    required int attemptNumber,
    required ApiTaskStatus status,
    Map<String, Object?>? response,
    int? httpStatusCode,
    String? safeErrorCode,
    String? safeErrorMessage,
    DateTime? nextAttemptAt,
    DateTime Function()? clock,
  }) async {
    if (status == ApiTaskStatus.running || status == ApiTaskStatus.pending) {
      throw ArgumentError.value(status, 'status', 'Waiting or final result required');
    }
    final now = (clock ?? DateTime.now)().millisecondsSinceEpoch;
    final safeResponse = response == null ? null : jsonEncode(_redactMap(response));
    final effectiveStatus = status == ApiTaskStatus.retryWait && attemptNumber >= 3
        ? ApiTaskStatus.failed : status;
    final db = await _db;
    await db.transaction((txn) async {
      final rows = await txn.query('api_tasks',
          where: 'id = ?', whereArgs: [taskId], limit: 1);
      if (rows.isEmpty) throw StateError('API task does not exist');
      if (rows.single['status'] != 'running' ||
          rows.single['attempts_count'] != attemptNumber) {
        throw StateError('API task attempt is no longer active');
      }
      final stored = ApiTask.storeStatus(effectiveStatus);
      await txn.update('api_task_attempts', {
        'finished_at': now,
        'http_status_code': httpStatusCode,
        'outcome': stored,
        'safe_error_code': _safeCode(safeErrorCode),
        'safe_error_message': safeErrorMessage == null ? null : _safeText(safeErrorMessage),
        'response_excerpt': safeResponse,
      }, where: 'task_id = ? AND attempt_number = ?',
          whereArgs: [taskId, attemptNumber]);
      await txn.update('api_tasks', {
        'status': stored,
        'response_json': safeResponse,
        'next_attempt_at': effectiveStatus == ApiTaskStatus.retryWait ? nextAttemptAt?.millisecondsSinceEpoch : null,
        'finished_at': effectiveStatus == ApiTaskStatus.retryWait ? null : now,
        'updated_at': now,
      }, where: 'id = ?', whereArgs: [taskId]);
      await txn.insert('api_task_events', {
        'task_id': taskId,
        'event_type': 'attempt_finished',
        'from_state': 'running',
        'to_state': stored,
        'message': _eventMessage(effectiveStatus, attemptNumber),
        'created_at': now,
      });
    });
  }

  Future<void> pauseQueue(String queue, {
    required bool paused,
    String? reason,
    DateTime Function()? clock,
  }) async {
    final now = (clock ?? DateTime.now)().millisecondsSinceEpoch;
    final db = await _db;
    await db.insert('api_queue_state', {
      'logical_queue': queue,
      'is_paused': paused ? 1 : 0,
      'pause_reason': paused ? reason : null,
      'updated_at': now,
    }, conflictAlgorithm: sqflite.ConflictAlgorithm.replace);
  }

  Future<void> pauseAll({
    required bool paused,
    String? reason,
    DateTime Function()? clock,
  }) async {
    final now = (clock ?? DateTime.now)().millisecondsSinceEpoch;
    final db = await _db;
    await db.transaction((txn) async {
      final rows = await txn.rawQuery('SELECT DISTINCT logical_queue FROM api_tasks');
      for (final row in rows) {
        await txn.insert('api_queue_state', {
          'logical_queue': row['logical_queue'],
          'is_paused': paused ? 1 : 0,
          'pause_reason': paused ? reason : null,
          'updated_at': now,
        }, conflictAlgorithm: sqflite.ConflictAlgorithm.replace);
      }
    });
  }

  /// Watchdog transition only. A stale request becomes uncertain, never retried.
  Future<int> markStaleRunningUncertain({
    Duration threshold = const Duration(minutes: 5),
    DateTime Function()? clock,
  }) async {
    final now = (clock ?? DateTime.now)();
    final cutoff = now.subtract(threshold).millisecondsSinceEpoch;
    final db = await _db;
    return db.transaction((txn) async {
      final rows = await txn.query('api_tasks',
          where: "status = 'running' AND started_at <= ?", whereArgs: [cutoff]);
      for (final row in rows) {
        final id = row['id'] as int;
        final changed = await txn.update('api_tasks', {
          'status': 'uncertain',
          'finished_at': now.millisecondsSinceEpoch,
          'updated_at': now.millisecondsSinceEpoch,
        }, where: "id = ? AND status = 'running'", whereArgs: [id]);
        if (changed != 1) continue;
        changedCount++;
        await txn.update('api_task_attempts', {
          'finished_at': now.millisecondsSinceEpoch,
          'outcome': 'uncertain',
          'safe_error_code': 'WATCHDOG_TIMEOUT',
          'safe_error_message': 'Задача выполнялась дольше пяти минут',
        }, where: 'task_id = ? AND attempt_number = ?',
            whereArgs: [id, row['attempts_count']]);
        await txn.insert('api_task_events', {
          'task_id': id,
          'event_type': 'watchdog_uncertain',
          'from_state': 'running',
          'to_state': 'uncertain',
          'message': 'Превышен порог watchdog; автоматический повтор запрещён',
          'created_at': now.millisecondsSinceEpoch,
        });
      }
      return changedCount;
    });
  }

  /// Called once after process startup. In-flight requests are uncertain because
  /// the app cannot know whether the remote service accepted them before exit.
  /// All dispatch is globally paused until the user explicitly confirms resume.
  Future<int> recoverAfterProcessRestart({
    DateTime Function()? clock,
  }) async {
    final now = (clock ?? DateTime.now)().millisecondsSinceEpoch;
    final db = await _db;
    return db.transaction((txn) async {
      final running = await txn.query('api_tasks',
          where: "status = 'running'");
      for (final row in running) {
        final id = row['id'] as int;
        await txn.update('api_tasks', {
          'status': 'uncertain',
          'finished_at': now,
          'updated_at': now,
        }, where: "id = ? AND status = 'running'", whereArgs: [id]);
        await txn.update('api_task_attempts', {
          'finished_at': now,
          'outcome': 'uncertain',
          'safe_error_code': 'PROCESS_RESTART',
          'safe_error_message': 'Приложение было закрыто во время выполнения запроса',
        }, where: 'task_id = ? AND attempt_number = ?',
            whereArgs: [id, row['attempts_count']]);
        await txn.insert('api_task_events', {
          'task_id': id,
          'event_type': 'process_restart',
          'from_state': 'running',
          'to_state': 'uncertain',
          'message': 'После перезапуска результат запроса не подтверждён; повтор запрещён',
          'created_at': now,
        });
      }
      await txn.insert('api_queue_state', {
        'logical_queue': '__all__',
        'is_paused': 1,
        'pause_reason': 'Требуется подтверждение после перезапуска',
        'requires_resume_confirmation': 1,
        'updated_at': now,
      }, conflictAlgorithm: sqflite.ConflictAlgorithm.replace);
      return running.length;
    });
  }

  Future<bool> requiresResumeConfirmation() async {
    final db = await _db;
    final rows = await db.query('api_queue_state',
        columns: ['requires_resume_confirmation'],
        where: "logical_queue = '__all__'", limit: 1);
    return rows.isNotEmpty && rows.single['requires_resume_confirmation'] == 1;
  }

  /// Explicit user action. Per-logical-queue manual pauses remain in force.
  Future<void> confirmResumeAfterRestart({
    DateTime Function()? clock,
  }) async {
    final now = (clock ?? DateTime.now)().millisecondsSinceEpoch;
    final db = await _db;
    await db.insert('api_queue_state', {
      'logical_queue': '__all__',
      'is_paused': 0,
      'pause_reason': null,
      'requires_resume_confirmation': 0,
      'updated_at': now,
    }, conflictAlgorithm: sqflite.ConflictAlgorithm.replace);
  }

  Future<List<ApiTask>> listTasks({
    String? logicalQueue,
    Set<ApiTaskStatus>? statuses,
    int limit = 200,
  }) async {
    final db = await _db;
    final clauses = <String>[];
    final args = <Object?>[];
    if (logicalQueue != null) {
      clauses.add('logical_queue = ?');
      args.add(logicalQueue);
    }
    if (statuses != null && statuses.isNotEmpty) {
      clauses.add('status IN (${List.filled(statuses.length, '?').join(',')})');
      args.addAll(statuses.map(ApiTask.storeStatus));
    }
    final rows = await db.query('api_tasks',
        where: clauses.isEmpty ? null : clauses.join(' AND '),
        whereArgs: args.isEmpty ? null : args,
        orderBy: 'fifo_sequence ASC', limit: limit);
    return rows.map(_fromRow).toList(growable: false);
  }

  Future<int> cancelPending({String? logicalQueue, DateTime Function()? clock}) async {
    final now = (clock ?? DateTime.now)().millisecondsSinceEpoch;
    final db = await _db;
    return db.transaction((txn) async {
      final where = logicalQueue == null
          ? "status IN ('pending','retry_wait')"
          : "status IN ('pending','retry_wait') AND logical_queue = ?";
      final rows = await txn.query('api_tasks',
          columns: ['id'], where: where,
          whereArgs: logicalQueue == null ? null : [logicalQueue]);
      for (final row in rows) {
        await txn.update('api_tasks', {
          'status': 'cancelled', 'finished_at': now, 'updated_at': now,
        }, where: 'id = ?', whereArgs: [row['id']]);
        await txn.insert('api_task_events', {
          'task_id': row['id'], 'event_type': 'cancelled',
          'to_state': 'cancelled',
          'message': 'Ожидающая задача отменена пользователем',
          'created_at': now,
        });
      }
      return rows.length;
    });
  }

  ApiTask _fromRow(Map<String, Object?> row) {
    final request = jsonDecode(row['request_json'] as String) as Map;
    final responseJson = row['response_json'] as String?;
    final response = responseJson == null ? null : jsonDecode(responseJson) as Map;
    return ApiTask(
      id: row['id'] as int,
      uid: row['task_uid'] as String,
      type: row['task_type'] as String,
      logicalQueue: row['logical_queue'] as String,
      status: ApiTask.parseStatus(row['status'] as String),
      fifoSequence: row['fifo_sequence'] as int,
      request: Map<String, Object?>.from(request),
      response: response == null ? null : Map<String, Object?>.from(response),
      attemptsCount: row['attempts_count'] as int,
      nextAttemptAt: _date(row['next_attempt_at']),
      startedAt: _date(row['started_at']),
      finishedAt: _date(row['finished_at']),
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
    );
  }

  DateTime? _date(Object? value) => value == null
      ? null : DateTime.fromMillisecondsSinceEpoch(value as int);

  Map<String, Object?> _redactMap(Map<String, Object?> source) {
    const secretKeys = {'authorization', 'access_token', 'accesstoken',
      'token', 'password', 'secret'};
    final result = <String, Object?>{};
    for (final entry in source.entries) {
      final key = entry.key.toLowerCase().replaceAll(RegExp(r'[-\s]'), '_');
      if (secretKeys.contains(key)) continue;
      final value = entry.value;
      if (value is Map) {
        result[entry.key] = _redactMap(Map<String, Object?>.from(value));
      } else if (value is List) {
        result[entry.key] = value.map((item) =>
          item is Map ? _redactMap(Map<String, Object?>.from(item)) : item).toList();
      } else {
        result[entry.key] = value;
      }
    }
    return result;
  }

  String? _safeCode(String? value) => value != null &&
      RegExp(r'^[A-Za-z0-9_.-]{1,64}$').hasMatch(value) ? value : null;

  String _safeText(String value) => value
      .replaceAll(RegExp(r'(bearer\s+)[A-Za-z0-9._~+/=-]+', caseSensitive: false), r'$1[СКРЫТО]')
      .replaceAll(RegExp(r'((?:access[-_ ]?)?token\s*[:=]\s*)[^\s,;]+', caseSensitive: false), r'$1[СКРЫТО]')
      .substring(0, value.length > 2000 ? 2000 : value.length);

  String _eventMessage(ApiTaskStatus status, int attempt) => switch (status) {
    ApiTaskStatus.retryWait => 'Временная ошибка; задача ожидает повторной попытки после попытки $attempt',
    ApiTaskStatus.succeeded => 'Задача успешно выполнена',
    ApiTaskStatus.failed => 'Задача завершилась ошибкой',
    ApiTaskStatus.uncertain => 'Результат не подтверждён; автоматический повтор запрещён',
    ApiTaskStatus.cancelled => 'Задача отменена',
    ApiTaskStatus.pending => 'Задача ожидает отправки',
    ApiTaskStatus.running => 'Задача выполняется',
  };
}
