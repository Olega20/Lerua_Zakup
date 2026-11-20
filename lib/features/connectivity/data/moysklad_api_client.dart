import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../domain/api_check_result.dart';

class MoySkladHttpResponse {
  const MoySkladHttpResponse({
    required this.statusCode,
    required this.body,
    this.headers = const {},
  });

  final int statusCode;
  final String body;
  final Map<String, String> headers;
}

abstract interface class MoySkladHttpTransport {
  Future<MoySkladHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
  });
}

class IoMoySkladHttpTransport implements MoySkladHttpTransport {
  IoMoySkladHttpTransport({HttpClient Function()? clientFactory})
    : _clientFactory = clientFactory ?? HttpClient.new;

  final HttpClient Function() _clientFactory;

  @override
  Future<MoySkladHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
  }) async {
    final client = _clientFactory()
      ..connectionTimeout = timeout
      ..autoUncompress = true;
    try {
      return await _performGet(client, uri, headers).timeout(timeout);
    } finally {
      client.close(force: true);
    }
  }

  Future<MoySkladHttpResponse> _performGet(
    HttpClient client,
    Uri uri,
    Map<String, String> headers,
  ) async {
    final request = await client.getUrl(uri);
    request.followRedirects = false;
    headers.forEach(request.headers.set);
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    final responseHeaders = <String, String>{};
    response.headers.forEach((name, values) {
      responseHeaders[name.toLowerCase()] = values.join(',');
    });
    return MoySkladHttpResponse(
      statusCode: response.statusCode,
      body: body,
      headers: responseHeaders,
    );
  }
}

class ApiResourceResult {
  const ApiResourceResult({
    required this.statusCode,
    this.data,
    this.retryAfter,
    this.errorCode,
  });
  final int statusCode;
  final Map<String, dynamic>? data;
  final Duration? retryAfter;
  final String? errorCode;
  bool get isSuccess => statusCode >= 200 && statusCode < 300 && data != null;
  bool get isRetryable =>
      statusCode == 408 || statusCode == 429 || statusCode >= 500;
}

class MoySkladApiClient {
  MoySkladApiClient({
    MoySkladHttpTransport? transport,
    this.timeout = const Duration(seconds: 10),
  }) : _transport = transport ?? IoMoySkladHttpTransport();

  static final Uri _employeeContextUri = Uri.https(
    'api.moysklad.ru',
    '/api/remap/1.2/context/employee/',
  );

  final MoySkladHttpTransport _transport;
  final Duration timeout;

  Future<ApiCheckResult> checkConnection(String? token) async {
    final normalizedToken = token?.trim();
    if (normalizedToken == null || normalizedToken.isEmpty) {
      return const ApiCheckResult(ApiCheckStatus.missingToken);
    }

    try {
      final response = await _transport.get(
        _employeeContextUri,
        timeout: timeout,
        headers: {
          HttpHeaders.authorizationHeader: 'Bearer $normalizedToken',
          HttpHeaders.acceptHeader: 'application/json',
          HttpHeaders.acceptEncodingHeader: 'gzip',
        },
      );

      if (response.statusCode == HttpStatus.ok) {
        try {
          final decoded = jsonDecode(response.body);
          if (decoded is Map<String, dynamic>) {
            return const ApiCheckResult(ApiCheckStatus.connected);
          }
        } on FormatException {
          // A successful status without a valid JSON object is not a valid check.
        }
        return const ApiCheckResult(
          ApiCheckStatus.invalidResponse,
          httpStatusCode: HttpStatus.ok,
        );
      }

      if (response.statusCode == HttpStatus.unauthorized) {
        return const ApiCheckResult(
          ApiCheckStatus.unauthorized,
          httpStatusCode: HttpStatus.unauthorized,
        );
      }
      if (response.statusCode == HttpStatus.forbidden) {
        return const ApiCheckResult(
          ApiCheckStatus.forbidden,
          httpStatusCode: HttpStatus.forbidden,
        );
      }
      if (response.statusCode == HttpStatus.tooManyRequests) {
        return ApiCheckResult(
          ApiCheckStatus.rateLimited,
          httpStatusCode: HttpStatus.tooManyRequests,
          retryAfter: _parseRetryAfter(response.headers['retry-after']),
        );
      }
      return ApiCheckResult(
        ApiCheckStatus.unavailable,
        httpStatusCode: response.statusCode,
      );
    } on TimeoutException {
      return const ApiCheckResult(ApiCheckStatus.timeout);
    } catch (_) {
      // Never expose transport exception text: it may contain request details.
      return const ApiCheckResult(ApiCheckStatus.unavailable);
    }
  }

  Future<ApiResourceResult> getResource(
    String? token,
    String path, {
    Map<String, String> query = const {},
  }) async {
    final normalized = token?.trim();
    if (normalized == null || normalized.isEmpty) {
      return const ApiResourceResult(
        statusCode: 401,
        errorCode: 'TOKEN_MISSING',
      );
    }
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    final uri = Uri.https('api.moysklad.ru', normalizedPath, query);
    try {
      final response = await _transport.get(
        uri,
        timeout: timeout,
        headers: {
          HttpHeaders.authorizationHeader: 'Bearer $normalized',
          HttpHeaders.acceptHeader: 'application/json',
          HttpHeaders.acceptEncodingHeader: 'gzip',
          'X-Lognex-Format-Metadata': 'true',
        },
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        String? code;
        try {
          final decoded = jsonDecode(response.body);
          if (decoded is Map) code = decoded['code']?.toString();
        } catch (_) {}
        return ApiResourceResult(
          statusCode: response.statusCode,
          retryAfter: _parseRetryAfter(response.headers['retry-after']),
          errorCode: code?.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), ''),
        );
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return ApiResourceResult(
          statusCode: response.statusCode,
          errorCode: 'INVALID_JSON_OBJECT',
        );
      }
      return ApiResourceResult(statusCode: response.statusCode, data: decoded);
    } on TimeoutException {
      return const ApiResourceResult(
        statusCode: 408,
        errorCode: 'NETWORK_TIMEOUT',
      );
    } on SocketException {
      return const ApiResourceResult(
        statusCode: 503,
        errorCode: 'NETWORK_UNAVAILABLE',
      );
    } on FormatException {
      return const ApiResourceResult(
        statusCode: 502,
        errorCode: 'INVALID_RESPONSE',
      );
    } catch (_) {
      return const ApiResourceResult(
        statusCode: 503,
        errorCode: 'TRANSPORT_ERROR',
      );
    }
  }

  Duration? _parseRetryAfter(String? value) {
    if (value == null) return null;
    final seconds = int.tryParse(value.trim());
    if (seconds != null && seconds >= 0) {
      return Duration(seconds: seconds);
    }
    try {
      final retryAt = HttpDate.parse(value);
      final delay = retryAt.difference(DateTime.now().toUtc());
      return delay.isNegative ? Duration.zero : delay;
    } on FormatException {
      return null;
    }
  }
}
