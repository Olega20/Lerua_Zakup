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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

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
