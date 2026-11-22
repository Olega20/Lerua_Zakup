import 'package:flutter_test/flutter_test.dart';
import 'package:lerua_zakup/core/storage/app_database.dart';
import 'package:lerua_zakup/features/connectivity/data/api_task_repository.dart';
import 'package:lerua_zakup/features/connectivity/domain/api_task.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late AppDatabase database;
  late ApiTaskRepository repository;

  setUp(() {
    database = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    repository = ApiTaskRepository(database: database);
  });

  tearDown(() async => database.close());

  test('deduplicates enqueue by stable task uid', () async {
    final first = await repository.enqueue(
      uid: 'stable-operation-1',
      type: 'catalog.products.refresh',
      logicalQueue: 'catalog',
      request: {'method': 'GET', 'path': '/entity/product'},
    );
    final duplicate = await repository.enqueue(
      uid: 'stable-operation-1',
      type: 'catalog.products.refresh',
      logicalQueue: 'catalog',
      request: {'method': 'GET', 'path': '/entity/product'},
    );

    expect(duplicate.id, first.id);
    expect((await repository.listTasks()).length, 1);
  });

  test('claims tasks in one global FIFO order across logical queues', () async {
    await repository.enqueue(
      uid: 'first',
      type: 'products',
      logicalQueue: 'catalog',
      request: {'path': '/entity/product'},
    );
    await repository.enqueue(
      uid: 'second',
      type: 'warehouses',
      logicalQueue: 'warehouses',
      request: {'path': '/entity/store'},
    );

    final first = await repository.claimNext();
    final second = await repository.claimNext();

    expect(first?.task.uid, 'first');
    expect(second?.task.uid, 'second');
    expect(first?.attemptNumber, 1);
    expect(second?.attemptNumber, 1);
  });

  test('does not claim a task from a paused logical queue', () async {
    await repository.enqueue(
      uid: 'paused',
      type: 'products',
      logicalQueue: 'catalog',
      request: {'path': '/entity/product'},
    );
    await repository.pauseQueue('catalog', paused: true, reason: 'manual');
    expect(await repository.claimNext(), isNull);
  });

  test('redacts secrets from persisted request and response data', () async {
    final task = await repository.enqueue(
      uid: 'safe',
      type: 'test',
      logicalQueue: 'test',
      request: {
        'path': '/entity/product',
        'headers': {'Authorization': 'Bearer hidden-value'},
        'token': 'hidden-value',
        'nested': {
          'access_token': 'hidden-value',
          'keep': 'yes',
          'items': [
            {'text': 'Bearer hidden-value'},
          ],
        },
        'diagnostic': 'Authorization: Bearer hidden-value; access_token=hidden-value; apiToken=hidden-value',
      },
    );
    expect(task.request, {
      'path': '/entity/product',
      'headers': <String, Object?>{},
      'nested': {
        'keep': 'yes',
        'items': [
          {'text': 'Bearer [СКРЫТО]'},
        ],
      },
      'diagnostic': 'Authorization: Bearer [СКРЫТО]; access_token=[СКРЫТО]; apiToken=[СКРЫТО]',
    });

    final claim = await repository.claimNext();
    await repository.finishAttempt(
      taskId: claim!.task.id,
      attemptNumber: claim.attemptNumber,
      status: ApiTaskStatus.succeeded,
      response: {'token': 'hidden-value', 'result': 'ok'},
    );
    final saved = (await repository.listTasks()).single;
    expect(saved.response, {'result': 'ok'});
  });

  test(
    'global pause also blocks queues created before or after the pause',
    () async {
      await repository.pauseAll(paused: true, reason: 'offline');
      await repository.enqueue(
        uid: 'created-during-pause',
        type: 'products',
        logicalQueue: 'catalog',
        request: {'path': '/entity/product'},
      );
      expect(await repository.claimNext(), isNull);
      await repository.pauseAll(paused: false);
      expect((await repository.claimNext())?.task.uid, 'created-during-pause');
    },
  );

  test('global resume preserves a manually paused logical queue', () async {
    await repository.enqueue(
      uid: 'manual-paused',
      type: 'products',
      logicalQueue: 'catalog',
      request: {'path': '/entity/product'},
    );
    await repository.pauseQueue('catalog', paused: true, reason: 'manual');
    await repository.pauseAll(paused: true, reason: 'offline');
    await repository.pauseAll(paused: false);
    expect(await repository.claimNext(), isNull);
    await repository.pauseQueue('catalog', paused: false);
    expect((await repository.claimNext())?.task.uid, 'manual-paused');
  });

  test('system resume cannot clear a user global pause', () async {
    await repository.enqueue(
      uid: 'user-paused',
      type: 'products',
      logicalQueue: 'catalog',
      request: {'path': '/entity/product'},
    );
    await repository.pauseAll(paused: true, reason: 'Пауза пользователя');
    await repository.resumeGlobalIfReason('Нет интернет-соединения');
    expect(await repository.claimNext(), isNull);
    await repository.pauseAll(paused: false);
    expect((await repository.claimNext())?.task.uid, 'user-paused');
  });

  test('conditional resume clears only the matching system pause', () async {
    await repository.enqueue(
      uid: 'system-paused',
      type: 'products',
      logicalQueue: 'catalog',
      request: {'path': '/entity/product'},
    );
    await repository.pauseAll(paused: true, reason: 'Нет интернет-соединения');
    await repository.resumeGlobalIfReason('МойСклад временно недоступен');
    expect(await repository.claimNext(), isNull);
    await repository.resumeGlobalIfReason('Нет интернет-соединения');
    expect((await repository.claimNext())?.task.uid, 'system-paused');
  });
  test(
    'startup resumes every logical queue and clears restart confirmation',
    () async {
      await repository.enqueue(
        uid: 'paused-catalog',
        type: 'catalog.refresh',
        logicalQueue: 'catalog',
        request: {'path': '/entity/product'},
      );
      await repository.enqueue(
        uid: 'paused-suppliers',
        type: 'suppliers.refresh',
        logicalQueue: 'suppliers',
        request: {'path': '/entity/counterparty'},
      );
      await repository.pauseQueue(
        'catalog',
        paused: true,
        reason: 'Пауза пользователя',
      );
      await repository.pauseQueue(
        'suppliers',
        paused: true,
        reason: 'Пауза пользователя',
      );
      await repository.pauseAll(
        paused: true,
        reason: 'Требуется подтверждение после перезапуска',
      );

      await repository.recoverAfterProcessRestart();
      await repository.resumeAllQueuesAfterProcessRestart();

      expect(await repository.requiresResumeConfirmation(), isFalse);
      expect(await repository.isQueuePaused(), isFalse);
      expect(await repository.isQueuePaused('catalog'), isFalse);
      expect(await repository.isQueuePaused('suppliers'), isFalse);
      expect((await repository.claimNext())?.task.uid, 'paused-catalog');
      expect((await repository.claimNext())?.task.uid, 'paused-suppliers');
    },
  );

  test(
    'restart does not request confirmation when no tasks are waiting',
    () async {
      expect(await repository.recoverAfterProcessRestart(), 0);
      expect(await repository.requiresResumeConfirmation(), isFalse);
    },
  );

  test(
    'watchdog marks a stale running task uncertain without retrying',
    () async {
      final start = DateTime(2026, 11, 20, 10);
      await repository.enqueue(
        uid: 'stale',
        type: 'document.create',
        logicalQueue: 'documents',
        request: {'path': '/entity/customerorder'},
        clock: () => start,
      );
      await repository.claimNext(clock: () => start);

      final changed = await repository.markStaleRunningUncertain(
        clock: () => start.add(const Duration(minutes: 6)),
      );

      expect(changed, 1);
      final task = (await repository.listTasks()).single;
      expect(task.status, ApiTaskStatus.uncertain);
      expect(task.attemptsCount, 1);
      expect(
        await repository.claimNext(
          clock: () => start.add(const Duration(minutes: 7)),
        ),
        isNull,
      );
    },
  );

  test(
    'restart marks in-flight request uncertain and waits for user confirmation',
    () async {
      await repository.enqueue(
        uid: 'in-flight',
        type: 'document.create',
        logicalQueue: 'documents',
        request: {'path': '/entity/customerorder'},
      );
      await repository.enqueue(
        uid: 'waiting',
        type: 'catalog.refresh',
        logicalQueue: 'catalog',
        request: {'path': '/entity/product'},
      );
      final running = await repository.claimNext();
      expect(running?.task.uid, 'in-flight');

      final recovered = await repository.recoverAfterProcessRestart();
      expect(recovered, 1);
      expect(await repository.requiresResumeConfirmation(), isTrue);
      expect(
        (await repository.listTasks()).first.status,
        ApiTaskStatus.uncertain,
      );
      expect(await repository.claimNext(), isNull);

      await repository.confirmResumeAfterRestart();
      expect(await repository.requiresResumeConfirmation(), isFalse);
      expect((await repository.claimNext())?.task.uid, 'waiting');
    },
  );

  test('manual retry creates a new FIFO task and preserves the failed task history', () async {
    await repository.enqueue(
      uid: 'manual-original',
      type: 'catalog',
      logicalQueue: 'catalog',
      request: {'method': 'GET', 'path': '/entity/product'},
    );
    final claim = await repository.claimNext();
    await repository.finishAttempt(
      taskId: claim!.task.id,
      attemptNumber: claim.attemptNumber,
      status: ApiTaskStatus.failed,
      safeErrorCode: 'HTTP_400',
      safeErrorMessage: 'Bad request',
    );
    final original = (await repository.listTasks()).single;
    final newId = await repository.retryFailed(original.id);
    final tasks = await repository.listTasks();
    expect(tasks, hasLength(2));
    expect(
      tasks.firstWhere((t) => t.id == original.id).status,
      ApiTaskStatus.failed,
    );
    final retry = tasks.firstWhere((t) => t.id == newId);
    expect(retry.status, ApiTaskStatus.pending);
    expect(retry.uid, contains(':manual:'));
    expect(retry.request['path'], '/entity/product');
  });

  test(
    'uncertain task can only be resolved after explicit manual review',
    () async {
      await repository.enqueue(
        uid: 'uncertain-review',
        type: 'write',
        logicalQueue: 'operations',
        request: {'method': 'POST', 'path': '/entity/demand'},
      );
      final claim = await repository.claimNext();
      await repository.finishAttempt(
        taskId: claim!.task.id,
        attemptNumber: claim.attemptNumber,
        status: ApiTaskStatus.uncertain,
        safeErrorCode: 'TIMEOUT',
        safeErrorMessage: 'Unknown result',
      );
      await repository.resolveUncertain(
        claim.task.id,
        confirmedSucceeded: false,
      );
      final task = (await repository.listTasks()).single;
      expect(task.status, ApiTaskStatus.failed);
      expect(task.attemptsCount, 1);
    },
  );

  test(
    'third temporary failure becomes final and is not claimed again',
    () async {
      final start = DateTime(2026, 11, 20, 10);
      await repository.enqueue(
        uid: 'retry-limit',
        type: 'catalog.refresh',
        logicalQueue: 'catalog',
        request: {'path': '/entity/product'},
        clock: () => start,
      );

      for (var attempt = 1; attempt <= 3; attempt++) {
        final claim = await repository.claimNext(
          clock: () => start.add(Duration(minutes: attempt * 2)),
        );
        expect(claim?.attemptNumber, attempt);
        await repository.finishAttempt(
          taskId: claim!.task.id,
          attemptNumber: claim.attemptNumber,
          status: ApiTaskStatus.retryWait,
          nextAttemptAt: start.add(Duration(minutes: attempt * 2 + 1)),
          clock: () => start.add(Duration(minutes: attempt * 2)),
        );
      }

      final task = (await repository.listTasks()).single;
      expect(task.status, ApiTaskStatus.failed);
      expect(task.attemptsCount, 3);
      expect(
        await repository.claimNext(
          clock: () => start.add(const Duration(minutes: 10)),
        ),
        isNull,
      );
    },
  );
  test(
    'deleteAllTasks removes tasks and cascades their attempt history',
    () async {
      await repository.enqueue(
        uid: 'delete-me',
        type: 'catalog.refresh',
        logicalQueue: 'catalog',
        request: {'method': 'GET', 'path': '/entity/organization'},
      );
      final claim = await repository.claimNext();
      await repository.finishAttempt(
        taskId: claim!.task.id,
        attemptNumber: claim.attemptNumber,
        status: ApiTaskStatus.failed,
        safeErrorCode: 'HTTP_403',
        safeErrorMessage: 'Forbidden',
      );

      expect(await repository.deleteAllTasks(), 1);
      expect(await repository.listTasks(), isEmpty);

      final db = await database.database;
      for (final table in [
        'api_task_attempts',
        'api_task_events',
        'journal_api_task_links',
      ]) {
        final rows = await db.rawQuery('SELECT COUNT(*) AS count FROM $table');
        expect(rows.single['count'], 0, reason: '$table should be empty');
      }
    },
  );
}
