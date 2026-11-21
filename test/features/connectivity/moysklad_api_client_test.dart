import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lerua_zakup/features/connectivity/data/moysklad_api_client.dart';
import 'package:lerua_zakup/features/connectivity/domain/api_check_result.dart';

class FakeMoySkladHttpTransport implements MoySkladHttpTransport {
  FakeMoySkladHttpTransport(this.response);

  final Future<MoySkladHttpResponse> Function()? response;
  int calls = 0;
  Uri? uri;
  Map<String, String>? headers;
  Duration? connectionTimeout;
  Duration? responseTimeout;

  @override
  Future<MoySkladHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration connectionTimeout,
    required Duration responseTimeout,
  }) async {
    calls++;
    this.uri = uri;
    this.headers = headers;
    this.connectionTimeout = connectionTimeout;
    this.responseTimeout = responseTimeout;
    return response == null
        ? const MoySkladHttpResponse(statusCode: 200, body: '{"rows":[]}')
        : response!();
  }
}

void main() {
  group('MoySkladApiClient', () {
    test('does not send a request when token is absent or blank', () async {
      final transport = FakeMoySkladHttpTransport(null);
      final client = MoySkladApiClient(transport: transport);

      expect(
        (await client.checkConnection(null)).status,
        ApiCheckStatus.missingToken,
      );
      expect(
        (await client.checkConnection('  ')).status,
        ApiCheckStatus.missingToken,
      );
      expect(transport.calls, 0);
    });

    test('requests the inventory list with required headers and resilient timeouts', () async {
      final transport = FakeMoySkladHttpTransport(null);
      final client = MoySkladApiClient(transport: transport);

      final result = await client.checkConnection('secret-token');

      expect(result.status, ApiCheckStatus.connected);
      expect(transport.uri!.host, 'api.moysklad.ru');
      expect(transport.uri!.path, '/api/remap/1.2/entity/inventory');
      expect(transport.uri!.queryParameters, {
        'limit': '1',
        'offset': '0',
        'order': 'created,desc',
      });
      String header(String name) => transport.headers!.entries
          .firstWhere((entry) => entry.key.toLowerCase() == name.toLowerCase())
          .value;
      expect(header('Authorization'), 'Bearer secret-token');
      expect(header('Accept'), 'application/json;charset=utf-8');
      expect(header('Accept-Encoding'), 'gzip');
      expect(header('User-Agent'), 'LZakup Android app');
      expect(transport.connectionTimeout, const Duration(seconds: 20));
      expect(transport.responseTimeout, const Duration(seconds: 30));
    });

    test('requires an inventory rows collection for HTTP 200', () async {
      final transport = FakeMoySkladHttpTransport(
        () async =>
            const MoySkladHttpResponse(statusCode: 200, body: 'not-json'),
      );

      final result = await MoySkladApiClient(transport: transport)
          .checkConnection('token');

      expect(result.status, ApiCheckStatus.invalidResponse);
      expect(result.httpStatusCode, 200);
    });

    test('rejects a successful response that is not an inventory collection', () async {
      final transport = FakeMoySkladHttpTransport(
        () async => const MoySkladHttpResponse(
          statusCode: 200,
          body: '{"id":"not-a-collection"}',
        ),
      );

      final result = await MoySkladApiClient(transport: transport)
          .checkConnection('token');

      expect(result.status, ApiCheckStatus.invalidResponse);
      expect(result.httpStatusCode, 200);
    });

    test('maps authentication and server status codes safely', () async {
      for (final testCase in [
        (401, ApiCheckStatus.unauthorized),
        (403, ApiCheckStatus.forbidden),
        (500, ApiCheckStatus.unavailable),
      ]) {
        final transport = FakeMoySkladHttpTransport(
          () async => MoySkladHttpResponse(
            statusCode: testCase.$1,
            body: '{"rows":[]}',
          ),
        );
        final result = await MoySkladApiClient(transport: transport)
            .checkConnection('token');
        expect(result.status, testCase.$2);
        expect(result.httpStatusCode, testCase.$1);
      }
    });

    test(
      'captures structured API and authentication error diagnostics',
      () async {
        final transport = FakeMoySkladHttpTransport(
          () async => const MoySkladHttpResponse(
            statusCode: 400,
            body: '{"errors":[{"error":"Некорректный запрос","code":101,"error_message":"Неверный формат запроса"}]}',
            headers: {
              'x-lognex-auth': 'AUTH_ERROR',
              'x-lognex-auth-message': 'Authentication diagnostic',
            },
          ),
        );

        final result = await MoySkladApiClient(transport: transport)
            .checkConnection('token');

        expect(result.status, ApiCheckStatus.unavailable);
        expect(result.httpStatusCode, 400);
        expect(result.apiErrorCode, '101');
        expect(result.apiErrorMessage, 'Неверный формат запроса');
        expect(result.authErrorCode, 'AUTH_ERROR');
        expect(result.authErrorMessage, 'Authentication diagnostic');
      },
    );
    test('parses Retry-After without retaining response body', () async {
      final transport = FakeMoySkladHttpTransport(
        () async => const MoySkladHttpResponse(
          statusCode: 429,
          body: '{"secret":"must-not-escape"}',
          headers: {'retry-after': '30'},
        ),
      );

      final result = await MoySkladApiClient(transport: transport)
          .checkConnection('token');

      expect(result.status, ApiCheckStatus.rateLimited);
      expect(result.retryAfter, const Duration(seconds: 30));
      expect(result.toString(), isNot(contains('must-not-escape')));
    });

    test(
      'maps timeout and transport exceptions without leaking details',
      () async {
        final timeoutTransport = FakeMoySkladHttpTransport(
          () => Future.error(TimeoutException('secret-token')),
        );
        final timeoutResult = await MoySkladApiClient(
          transport: timeoutTransport,
        ).checkConnection('secret-token');
        expect(timeoutResult.status, ApiCheckStatus.timeout);
        expect(timeoutResult.toString(), isNot(contains('secret-token')));

        final failedTransport = FakeMoySkladHttpTransport(
          () => Future.error(StateError('Authorization: secret-token')),
        );
        final failedResult = await MoySkladApiClient(transport: failedTransport)
            .checkConnection('secret-token');
        expect(failedResult.status, ApiCheckStatus.unavailable);
        expect(failedResult.toString(), isNot(contains('secret-token')));
      },
    );
  });
}
