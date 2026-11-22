import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lerua_zakup/core/storage/app_database.dart';
import 'package:lerua_zakup/core/storage/secure_token_store.dart';
import 'package:lerua_zakup/features/connectivity/data/api_task_dispatcher.dart';
import 'package:lerua_zakup/features/connectivity/data/api_task_repository.dart';
import 'package:lerua_zakup/features/connectivity/data/moysklad_api_client.dart';
import 'package:lerua_zakup/features/connectivity/domain/api_task_execution_exception.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _TokenStore implements SecureTokenStore {
  @override
  Future<String?> readToken() async => 'test-token';
  @override
  Future<void> writeToken(String value) async {}
  @override
  Future<void> deleteToken() async {}
}

class _ForbiddenTransport implements MoySkladHttpTransport {
  @override
  Future<MoySkladHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration connectionTimeout,
    required Duration responseTimeout,
  }) async => const MoySkladHttpResponse(
    statusCode: 403,
    body: '{"errors":[{"code":3004,"error_message":"Нет прав на чтение организаций"}]}',
  );
}

class _SuccessTransport implements MoySkladHttpTransport {
  int requests = 0;

  @override
  Future<MoySkladHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration connectionTimeout,
    required Duration responseTimeout,
  }) async {
    requests++;
    return const MoySkladHttpResponse(statusCode: 200, body: '{"rows":[]}');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  test('dispatcher subscribes before recovery and receives an immediate online event', () async {
    final database = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    final internet = StreamController<bool>.broadcast();
    final transport = _SuccessTransport();
    final dispatcher = ApiTaskDispatcher(
      repository: ApiTaskRepository(database: database),
      apiClient: MoySkladApiClient(transport: transport),
      tokenStore: _TokenStore(),
      internet: internet.stream,
    );

    try {
      final starting = dispatcher.start();
      // This event is emitted while recoverAfterProcessRestart is awaiting
      // the database. A late subscription would permanently miss it.
      internet.add(true);
      await starting;

      final response = await dispatcher.requestGet(
        uid: 'startup-race',
        type: 'products',
        logicalQueue: 'catalog',
        path: '/entity/product',
      );

      expect(response, {'rows': []});
      expect(transport.requests, 1);
    } finally {
      await dispatcher.dispose();
      await internet.close();
      await database.close();
    }
  });

  test('dispatcher uses current connectivity snapshot when the event predates start', () async {
    final database = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    final internet = StreamController<bool>.broadcast();
    final transport = _SuccessTransport();
    final dispatcher = ApiTaskDispatcher(
      repository: ApiTaskRepository(database: database),
      apiClient: MoySkladApiClient(transport: transport),
      tokenStore: _TokenStore(),
      internet: internet.stream,
      connectivitySnapshot: () => true,
    );

    try {
      await dispatcher.start();
      final response = await dispatcher.requestGet(
        uid: 'startup-snapshot',
        type: 'products',
        logicalQueue: 'catalog',
        path: '/entity/product',
      );
      expect(response, {'rows': []});
      expect(transport.requests, 1);
    } finally {
      await dispatcher.dispose();
      await internet.close();
      await database.close();
    }
  });

  test(
    'tasks remain queued offline and execute after connectivity is restored',
    () async {
      final database = AppDatabase(
        databaseFactory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      final internet = StreamController<bool>.broadcast();
      final transport = _SuccessTransport();
      final repository = ApiTaskRepository(database: database);
      final dispatcher = ApiTaskDispatcher(
        repository: repository,
        apiClient: MoySkladApiClient(transport: transport),
        tokenStore: _TokenStore(),
        internet: internet.stream,
      );

      try {
        await dispatcher.start();
        await dispatcher.enqueueGet(
          uid: 'offline-queued',
          type: 'products',
          logicalQueue: 'catalog',
          path: '/entity/product',
        );
        expect((await repository.listTasks()).single.status.name, 'pending');
        expect(transport.requests, 0);

        internet.add(true);
        final response = await dispatcher.requestGet(
          uid: 'offline-queued',
          type: 'products',
          logicalQueue: 'catalog',
          path: '/entity/product',
        );
        expect(response, {'rows': []});
        expect(transport.requests, 1);
      } finally {
        await dispatcher.dispose();
        await internet.close();
        await database.close();
      }
    },
  );

  test(
    'requestGet exposes HTTP error details from task attempt history',
    () async {
      final database = AppDatabase(
        databaseFactory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      final internet = StreamController<bool>.broadcast();
      final dispatcher = ApiTaskDispatcher(
        repository: ApiTaskRepository(database: database),
        apiClient: MoySkladApiClient(transport: _ForbiddenTransport()),
        tokenStore: _TokenStore(),
        internet: internet.stream,
      );

      try {
        await dispatcher.start();
        internet.add(true);
        await Future<void>.delayed(const Duration(milliseconds: 10));

        await expectLater(
          dispatcher.requestGet(
            uid: 'organization-test',
            type: 'organizations',
            logicalQueue: 'organizations',
            path: '/entity/organization',
          ),
          throwsA(
            isA<ApiTaskExecutionException>()
                .having((e) => e.httpStatusCode, 'HTTP status', 403)
                .having((e) => e.safeErrorCode, 'API error code', '3004')
                .having(
                  (e) => e.safeErrorMessage,
                  'API error message',
                  'Нет прав на чтение организаций',
                )
                .having(
                  (e) => e.response?['errors'],
                  'response body',
                  isA<List>(),
                ),
          ),
        );
      } finally {
        await dispatcher.dispose();
        await internet.close();
        await database.close();
      }
    },
  );
}
