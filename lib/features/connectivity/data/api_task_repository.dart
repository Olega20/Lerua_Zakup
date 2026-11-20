import 'dart:convert';

import 'package:sqflite/sqflite.dart' as sqflite;

import '../../../core/storage/app_database.dart';
import '../domain/api_task.dart';

/// Durable task storage for one global FIFO dispatcher and multiple logical queues.
/// Credentials and Authorization headers must never be included in request data.
class ApiTaskRepository {
  // Keep the public named argument stable for existing callers.
  // ignore: prefer_initializing_formals
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
      final existing = await txn.query(
        'api_tasks',
        where: 'task_uid = ?',
        whereArgs: [uid],
        limit: 1,
      );
      if (existing.isNotEmpty) return _fromRow(existing.first);

      final sequenceRows = await txn.rawQuery(
        'SELECT COALESCE(MAX(fifo_sequence), 0) + 1 AS next_sequence FROM api_tasks',
      );
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
      return _fromRow(
        (await txn.query(
          'api_tasks',
          where: 'id = ?',
          whereArgs: [id],
          limit: 1,
        )).single,
      );
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
      final rows = await txn.rawQuery(
        '''
        SELECT t.* FROM api_tasks t
        WHERE t.status IN ('pending', 'retry_wait')
          AND t.attempts_count < ?
          AND (t.next_attempt_at IS NULL OR t.next_attempt_at <= ?)
          AND NOT EXISTS (
            SELECT 1 FROM api_queue_state q
            WHERE q.logical_queue IN (t.logical_queue, '__all__') AND (q.is_paused = 1 OR q.requires_resume_confirmation = 1)
          )
        ORDER BY t.fifo_sequence ASC LIMIT 1
      ''',
        [maximumAttempts, now],
      );
      if (rows.isEmpty) return null;

      final row = rows.first;
      final id = row['id'] as int;
      final oldStatus = row['status'] as String;
      final attempt = (row['attempts_count'] as int) + 1;
      final changed = await txn.update(
        'api_tasks',
        {
          'status': 'running',
          'attempts_count': attempt,
          'started_at': now,
          'updated_at': now,
          'next_attempt_at': null,
        },
        where: 'id = ? AND status = ?',
        whereArgs: [id, oldStatus],
      );
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
      final claimed = (await txn.query(
        'api_tasks',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      )).single;
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
      throw ArgumentError.value(
        status,
        'status',
        'Waiting or final result required',
      );
    }
    final now = (clock ?? DateTime.now)().millisecondsSinceEpoch;
    final safeResponse = response == null
        ? null
        : jsonEncode(_redactMap(response));
    final effectiveStatus =
        status == ApiTaskStatus.retryWait && attemptNumber >= 3
        ? ApiTaskStatus.failed
        : status;
    final db = await _db;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'api_tasks',
        where: 'id = ?',
        whereArgs: [taskId],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('API task does not exist');
      if (rows.single['status'] != 'running' ||
          rows.single['attempts_count'] != attemptNumber) {
        throw StateError('API task attempt is no longer active');
      }
      final stored = ApiTask.storeStatus(effectiveStatus);
      await txn.update(
        'api_task_attempts',
        {
          'finished_at': now,
          'http_status_code': httpStatusCode,
          'outcome': stored,
          'safe_error_code': _safeCode(safeErrorCode),
          'safe_error_message': safeErrorMessage == null
              ? null
              : _safeText(safeErrorMessage),
          'response_excerpt': safeResponse,
        },
        where: 'task_id = ? AND attempt_number = ?',
        whereArgs: [taskId, attemptNumber],
      );
      await txn.update(
        'api_tasks',
        {
          'status': stored,
          'response_json': safeResponse,
          'next_attempt_at': effectiveStatus == ApiTaskStatus.retryWait
              ? nextAttemptAt?.millisecondsSinceEpoch
              : null,
          'finished_at': effectiveStatus == ApiTaskStatus.retryWait
              ? null
              : now,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [taskId],
      );
      await txn.insert('api_task_events', {
        'task_id': taskId,
        'event_type': 'attempt_finished',
        'from_state': 'running',
        'to_state': stored,
        'message': _eventMessage(effectiveStatus, attemptNumber),
        'created_at': now,
      });
      if (effectiveStatus != ApiTaskStatus.succeeded) {
        await txn.insert('warehouse_log', {
          'timestamp': now,
          'level': effectiveStatus == ApiTaskStatus.retryWait
              ? 'warning'
              : 'error',
          'event_type': effectiveStatus == ApiTaskStatus.uncertain
              ? 'apiTaskUncertain'
              : 'apiTaskFailed',
          'description': _safeText(
            safeErrorMessage ?? _eventMessage(effectiveStatus, attemptNumber),
          ),
          'http_status_code': httpStatusCode,
          'api_error_code': _safeCode(safeErrorCode),
          'component': 'Менеджер API',
          'error_code': _safeCode(safeErrorCode) ?? 'API_TASK_FAILED',
          'recommended_action': effectiveStatus == ApiTaskStatus.uncertain
              ? 'Проверьте результат операции в МойСклад вручную; не повторяйте автоматически.'
              : effectiveStatus == ApiTaskStatus.retryWait
              ? 'Задача будет повторена автоматически после паузы.'
              : 'Проверьте настройки доступа и детали задачи; при необходимости повторите вручную.',
          'technical_details':
              'Тип задачи: ${_safeText(rows.single['task_type'] as String)}; UID: ${_safeText(rows.single['task_uid'] as String)}',
          'task_id': rows.single['task_uid'],
          'attempt_number': attemptNumber,
        });
        await _trimWarehouseLog(txn);
      }
    });
  }

  Future<void> pauseQueue(
    String queue, {
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
      final existing = await txn.query(
        'api_queue_state',
        where: "logical_queue = '__all__'",
        limit: 1,
      );
      if (existing.isEmpty) {
        await txn.insert('api_queue_state', {
          'logical_queue': '__all__',
          'is_paused': paused ? 1 : 0,
          'pause_reason': paused ? reason : null,
          'requires_resume_confirmation': 0,
          'updated_at': now,
        });
      } else {
        if (paused && existing.first['pause_reason'] == 'Пауза пользователя') {
          return;
        }
        // Global pause is independent from logical queue pauses and the
        // post-restart confirmation latch.
        await txn.update('api_queue_state', {
          'is_paused': paused ? 1 : 0,
          'pause_reason': paused ? reason : null,
          'updated_at': now,
        }, where: "logical_queue = '__all__'");
      }
    });
  }

  Future<void> resumeGlobalIfReason(
    String reason, {
    DateTime Function()? clock,
  }) async {
    final now = (clock ?? DateTime.now)().millisecondsSinceEpoch;
    final db = await _db;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'api_queue_state',
        where: "logical_queue = '__all__'",
        limit: 1,
      );
      if (rows.isEmpty || rows.first['pause_reason'] != reason) return;
      await txn.update('api_queue_state', {
        'is_paused': 0,
        'pause_reason': null,
        'updated_at': now,
      }, where: "logical_queue = '__all__'");
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
      var changedCount = 0;
      final rows = await txn.query(
        'api_tasks',
        where: "status = 'running' AND started_at <= ?",
        whereArgs: [cutoff],
      );
      for (final row in rows) {
        final id = row['id'] as int;
        final changed = await txn.update(
          'api_tasks',
          {
            'status': 'uncertain',
            'finished_at': now.millisecondsSinceEpoch,
            'updated_at': now.millisecondsSinceEpoch,
          },
          where: "id = ? AND status = 'running'",
          whereArgs: [id],
        );
        if (changed != 1) continue;
        changedCount++;
        await txn.update(
          'api_task_attempts',
          {
            'finished_at': now.millisecondsSinceEpoch,
            'outcome': 'uncertain',
            'safe_error_code': 'WATCHDOG_TIMEOUT',
            'safe_error_message': 'Задача выполнялась дольше пяти минут',
          },
          where: 'task_id = ? AND attempt_number = ?',
          whereArgs: [id, row['attempts_count']],
        );
        await txn.insert('api_task_events', {
          'task_id': id,
          'event_type': 'watchdog_uncertain',
          'from_state': 'running',
          'to_state': 'uncertain',
          'message': 'Превышен порог watchdog; автоматический повтор запрещён',
          'created_at': now.millisecondsSinceEpoch,
        });
        await txn.insert('warehouse_log', {
          'timestamp': now.millisecondsSinceEpoch,
          'level': 'error',
          'event_type': 'apiTaskUncertain',
          'description': 'Задача выполнялась дольше пяти минут; результат запроса неизвестен.',
          'component': 'Менеджер API',
          'error_code': 'WATCHDOG_TIMEOUT',
          'recommended_action': 'Проверьте результат в МойСклад вручную. Не запускайте автоматический повтор.',
          'task_id': row['task_uid'],
          'attempt_number': row['attempts_count'],
        });
        await _trimWarehouseLog(txn);
      }
      return changedCount;
    });
  }

  /// Called once after process startup. In-flight requests are uncertain because
  /// the app cannot know whether the remote service accepted them before exit.
  /// All dispatch is globally paused until the user explicitly confirms resume.
  Future<int> recoverAfterProcessRestart({DateTime Function()? clock}) async {
    final now = (clock ?? DateTime.now)().millisecondsSinceEpoch;
    final db = await _db;
    return db.transaction((txn) async {
      final activeTasks = await txn.query(
        'api_tasks',
        where: "status IN ('pending', 'retry_wait', 'running')",
      );
      final running = activeTasks
          .where((row) => row['status'] == 'running')
          .toList();
      for (final row in running) {
        final id = row['id'] as int;
        await txn.update(
          'api_tasks',
          {'status': 'uncertain', 'finished_at': now, 'updated_at': now},
          where: "id = ? AND status = 'running'",
          whereArgs: [id],
        );
        await txn.update(
          'api_task_attempts',
          {
            'finished_at': now,
            'outcome': 'uncertain',
            'safe_error_code': 'PROCESS_RESTART',
            'safe_error_message':
                'Приложение было закрыто во время выполнения запроса',
          },
          where: 'task_id = ? AND attempt_number = ?',
          whereArgs: [id, row['attempts_count']],
        );
        await txn.insert('api_task_events', {
          'task_id': id,
          'event_type': 'process_restart',
          'from_state': 'running',
          'to_state': 'uncertain',
          'message': 'После перезапуска результат запроса не подтверждён; повтор запрещён',
          'created_at': now,
        });
        await txn.insert('warehouse_log', {
          'timestamp': now,
          'level': 'error',
          'event_type': 'apiTaskUncertain',
          'description':
              'Приложение было закрыто во время запроса; результат неизвестен.',
          'component': 'Менеджер API',
          'error_code': 'PROCESS_RESTART',
          'recommended_action': 'Проверьте результат операции в МойСклад вручную перед любым повтором.',
          'task_id': row['task_uid'],
          'attempt_number': row['attempts_count'],
        });
        await _trimWarehouseLog(txn);
      }
      if (activeTasks.isNotEmpty) {
        await txn.insert('api_queue_state', {
          'logical_queue': '__all__',
          'is_paused': 1,
          'pause_reason': 'Требуется подтверждение после перезапуска',
          'requires_resume_confirmation': 1,
          'updated_at': now,
        }, conflictAlgorithm: sqflite.ConflictAlgorithm.replace);
      }
      return running.length;
    });
  }

  Future<bool> requiresResumeConfirmation() async {
    final db = await _db;
    final rows = await db.query(
      'api_queue_state',
      columns: ['requires_resume_confirmation'],
      where: "logical_queue = '__all__'",
      limit: 1,
    );
    return rows.isNotEmpty && rows.single['requires_resume_confirmation'] == 1;
  }

  /// Explicit user action. Per-logical-queue manual pauses remain in force.
  Future<void> confirmResumeAfterRestart({DateTime Function()? clock}) async {
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

  Future<bool> isQueuePaused([String queue = '__all__']) async {
    final db = await _db;
    final rows = await db.query(
      'api_queue_state',
      where: 'logical_queue = ?',
      whereArgs: [queue],
      limit: 1,
    );
    return rows.isNotEmpty && rows.first['is_paused'] == 1;
  }

  Future<Map<String, List<Map<String, Object?>>>> taskHistory(
    int taskId,
  ) async {
    final db = await _db;
    final attempts = await db.query(
      'api_task_attempts',
      where: 'task_id = ?',
      whereArgs: [taskId],
      orderBy: 'attempt_number',
    );
    final events = await db.query(
      'api_task_events',
      where: 'task_id = ?',
      whereArgs: [taskId],
      orderBy: 'created_at,id',
    );
    return {'attempts': attempts, 'events': events};
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
    final rows = await db.query(
      'api_tasks',
      where: clauses.isEmpty ? null : clauses.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'fifo_sequence ASC',
      limit: limit,
    );
    return rows.map(_fromRow).toList(growable: false);
  }

  Future<int> retryFailed(int taskId, {DateTime Function()? clock}) async {
    final now = (clock ?? DateTime.now)().millisecondsSinceEpoch;
    final db = await _db;
    return db.transaction((txn) async {
      final rows = await txn.query(
        'api_tasks',
        where: 'id = ? AND status = ?',
        whereArgs: [taskId, 'failed'],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw StateError(
          'Повтор разрешён только для задачи со статусом «Ошибка»',
        );
      }
      final old = rows.single;
      final uid = '${old['task_uid']}:manual:$now';
      final sequenceRows = await txn.rawQuery(
        'SELECT COALESCE(MAX(fifo_sequence),0)+1 AS n FROM api_tasks',
      );
      final sequence = sequenceRows.first['n'] as int;
      final newId = await txn.insert('api_tasks', {
        'task_uid': uid,
        'task_type': old['task_type'],
        'logical_queue': old['logical_queue'],
        'status': 'pending',
        'fifo_sequence': sequence,
        'request_json': old['request_json'],
        'attempts_count': 0,
        'created_at': now,
        'updated_at': now,
      });
      final links = await txn.query(
        'journal_api_task_links',
        where: 'task_id = ?',
        whereArgs: [taskId],
      );
      for (final link in links) {
        await txn.insert('journal_api_task_links', {
          'journal_entry_id': link['journal_entry_id'],
          'task_id': newId,
          'relation_type': link['relation_type'],
        });
      }
      await txn.insert('api_task_events', {
        'task_id': taskId,
        'event_type': 'manual_retry_created',
        'to_state': 'failed',
        'message': 'Создана отдельная задача ручного повтора $uid',
        'created_at': now,
      });
      await txn.insert('api_task_events', {
        'task_id': newId,
        'event_type': 'created',
        'to_state': 'pending',
        'message': 'Задача создана вручную после проверки предыдущей ошибки',
        'created_at': now,
      });
      return newId;
    });
  }

  Future<void> resolveUncertain(
    int taskId, {
    required bool confirmedSucceeded,
    DateTime Function()? clock,
  }) async {
    final now = (clock ?? DateTime.now)().millisecondsSinceEpoch;
    final db = await _db;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'api_tasks',
        where: 'id = ? AND status = ?',
        whereArgs: [taskId, 'uncertain'],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw StateError('Задача не находится в неопределённом состоянии');
      }
      final next = confirmedSucceeded ? 'succeeded' : 'failed';
      await txn.update(
        'api_tasks',
        {'status': next, 'finished_at': now, 'updated_at': now},
        where: 'id = ?',
        whereArgs: [taskId],
      );
      await txn.insert('api_task_events', {
        'task_id': taskId,
        'event_type': 'manual_resolution',
        'from_state': 'uncertain',
        'to_state': next,
        'message': confirmedSucceeded
            ? 'Пользователь подтвердил выполнение во внешней системе'
            : 'Пользователь подтвердил отсутствие выполнения; автоматический повтор не запускался',
        'created_at': now,
      });
    });
  }

  Future<int> cancelPending({
    String? logicalQueue,
    DateTime Function()? clock,
  }) async {
    final now = (clock ?? DateTime.now)().millisecondsSinceEpoch;
    final db = await _db;
    return db.transaction((txn) async {
      final where = logicalQueue == null
          ? "status IN ('pending','retry_wait')"
          : "status IN ('pending','retry_wait') AND logical_queue = ?";
      final rows = await txn.query(
        'api_tasks',
        columns: ['id'],
        where: where,
        whereArgs: logicalQueue == null ? null : [logicalQueue],
      );
      for (final row in rows) {
        await txn.update(
          'api_tasks',
          {'status': 'cancelled', 'finished_at': now, 'updated_at': now},
          where: 'id = ?',
          whereArgs: [row['id']],
        );
        await txn.insert('api_task_events', {
          'task_id': row['id'],
          'event_type': 'cancelled',
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
    final response = responseJson == null
        ? null
        : jsonDecode(responseJson) as Map;
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

  DateTime? _date(Object? value) =>
      value == null ? null : DateTime.fromMillisecondsSinceEpoch(value as int);

  Map<String, Object?> _redactMap(Map<String, Object?> source) {
    const secretKeys = {
      'authorization',
      'access_token',
      'accesstoken',
      'token',
      'password',
      'secret',
    };
    final result = <String, Object?>{};
    for (final entry in source.entries) {
      final key = entry.key.toLowerCase().replaceAll(RegExp(r'[-\s]'), '_');
      if (secretKeys.contains(key) ||
          key.replaceAll('_', '').contains('token') ||
          key.contains('password') ||
          key.contains('secret')) {
        continue;
      }
      final value = entry.value;
      if (value is Map) {
        result[entry.key] = _redactMap(Map<String, Object?>.from(value));
      } else if (value is List) {
        result[entry.key] = value.map(_redactValue).toList();
      } else {
        result[entry.key] = _redactValue(value);
      }
    }
    return result;
  }

  Future<void> _trimWarehouseLog(sqflite.Transaction txn) async {
    await txn.rawDelete(
      '''DELETE FROM warehouse_log WHERE id NOT IN
      (SELECT id FROM warehouse_log ORDER BY timestamp DESC, id DESC LIMIT 500)''',
    );
  }

  Object? _redactValue(Object? value) {
    if (value is Map) return _redactMap(Map<String, Object?>.from(value));
    if (value is List) return value.map(_redactValue).toList();
    if (value is String) return _safeText(value);
    return value;
  }

  String? _safeCode(String? value) =>
      value != null && RegExp(r'^[A-Za-z0-9_.-]{1,64}$').hasMatch(value)
      ? value
      : null;

  String _safeText(String value) {
    final safe = value
        .replaceAllMapped(
          RegExp(r'(bearer\s+)[A-Za-z0-9._~+/=-]+', caseSensitive: false),
          (match) => '${match[1]}[СКРЫТО]',
        )
        .replaceAllMapped(
          RegExp(
            r'((?:(?:access|api)[-_ ]?)?token\s*[:=]\s*)[^\s,;]+',
            caseSensitive: false,
          ),
          (match) => '${match[1]}[СКРЫТО]',
        )
        .replaceAllMapped(
          RegExp(
            r'((?:password|secret)\s*[:=]\s*)[^\s,;]+',
            caseSensitive: false,
          ),
          (match) => '${match[1]}[СКРЫТО]',
        );
    return safe.length > 2000 ? safe.substring(0, 2000) : safe;
  }

  String _eventMessage(ApiTaskStatus status, int attempt) => switch (status) {
    ApiTaskStatus.retryWait =>
      'Временная ошибка; задача ожидает повторной попытки после попытки $attempt',
    ApiTaskStatus.succeeded => 'Задача успешно выполнена',
    ApiTaskStatus.failed => 'Задача завершилась ошибкой',
    ApiTaskStatus.uncertain =>
      'Результат не подтверждён; автоматический повтор запрещён',
    ApiTaskStatus.cancelled => 'Задача отменена',
    ApiTaskStatus.pending => 'Задача ожидает отправки',
    ApiTaskStatus.running => 'Задача выполняется',
  };
}
