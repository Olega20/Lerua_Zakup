import 'package:flutter_test/flutter_test.dart';
import 'package:lerua_zakup/features/warehouse_log/data/warehouse_log_repository.dart';
import 'package:lerua_zakup/features/warehouse_log/data/warehouse_log_storage.dart';
import 'package:lerua_zakup/features/warehouse_log/domain/warehouse_log_entry.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  group('WarehouseLogRepository with SQLite', () {
    late SqfliteWarehouseLogStorage storage;
    late WarehouseLogRepository repository;

    setUp(() {
      storage = SqfliteWarehouseLogStorage(
        databaseFactory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      repository = WarehouseLogRepository(storage: storage);
    });

    tearDown(() async {
      await storage.close();
    });

    test('persists records and returns newest first', () async {
      await repository.record(
        level: WarehouseLogLevel.info,
        type: WarehouseLogEventType.checkStarted,
        description: 'Проверка подключения запущена',
      );
      await repository.record(
        level: WarehouseLogLevel.info,
        type: WarehouseLogEventType.checkSucceeded,
        description: 'Подключение подтверждено',
        httpStatusCode: 200,
      );

      final entries = await repository.latest();
      expect(entries, hasLength(2));
      expect(entries.first.type, WarehouseLogEventType.checkSucceeded);
      expect(entries.last.type, WarehouseLogEventType.checkStarted);
      expect(entries.first.httpStatusCode, 200);
    });

    test('retains only the latest 500 entries', () async {
      for (var index = 0; index < 505; index++) {
        await repository.record(
          level: WarehouseLogLevel.info,
          type: WarehouseLogEventType.checkStarted,
          description: 'Запись $index',
        );
      }

      final entries = await repository.latest();
      expect(entries, hasLength(500));
      expect(entries.first.description, 'Запись 504');
      expect(entries.last.description, 'Запись 5');
    });

    test('sanitizes API codes and keeps safe diagnostic text', () async {
      await repository.record(
        level: WarehouseLogLevel.error,
        type: WarehouseLogEventType.apiUnavailable,
        description: 'МойСклад недоступен',
        apiErrorCode: 'Authorization: secret-token',
      );

      final entry = (await repository.latest()).single;
      expect(entry.apiErrorCode, isNull);
      expect(entry.toSafeText(), isNot(contains('secret-token')));
    });

    test('clears all stored records', () async {
      await repository.record(
        level: WarehouseLogLevel.warning,
        type: WarehouseLogEventType.timeout,
        description: 'Время ожидания истекло',
      );
      await repository.clear();
      expect(await repository.latest(), isEmpty);
    });
  });
}
