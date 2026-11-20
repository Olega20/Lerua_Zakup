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
      uid: 'first', type: 'products', logicalQueue: 'catalog',
      request: {'path': '/entity/product'},
    );
    await repository.enqueue(
      uid: 'second', type: 'warehouses', logicalQueue: 'warehouses',
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
      uid: 'paused', type: 'products', logicalQueue: 'catalog',
      request: {'path': '/entity/product'},
    );
    await repository.pauseQueue('catalog', paused: true, reason: 'manual');
    expect(await repository.claimNext(), isNull);
  });

  test('redacts secrets from persisted request and response data', () async {
    final task = await repository.enqueue(
      uid: 'safe', type: 'test', logicalQueue: 'test',
      request: {
        'path': '/entity/product',
        'headers': {'Authorization': 'Bearer hidden-value'},
        'token': 'hidden-value',
        'nested': {'access_token': 'hidden-value', 'keep': 'yes'},
      },
    );
    expect(task.request, {
      'path': '/entity/product',
      'headers': <String, Object?>{},
      'nested': {'keep': 'yes'},
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

  test('watchdog marks a stale running task uncertain without retrying', () async {
    final start = DateTime(2026, 11, 20, 10);
    await repository.enqueue(
      uid: 'stale', type: 'document.create', logicalQueue: 'documents',
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
    expect(await repository.claimNext(
      clock: () => start.add(const Duration(minutes: 7)),
    ), isNull);
  });

  test('third temporary failure becomes final and is not claimed again', () async {
    final start = DateTime(2026, 11, 20, 10);
    await repository.enqueue(
      uid: 'retry-limit', type: 'catalog.refresh', logicalQueue: 'catalog',
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
    expect(await repository.claimNext(
      clock: () => start.add(const Duration(minutes: 10)),
    ), isNull);
  });
}
