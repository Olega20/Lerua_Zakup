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
    required Duration connectionTimeout,
    required Duration responseTimeout,
  });
}

abstract interface class MoySkladHttpWriteTransport {
  Future<MoySkladHttpResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    required Object body,
    required Duration connectionTimeout,
    required Duration responseTimeout,
  });
}

class IoMoySkladHttpTransport
    implements MoySkladHttpTransport, MoySkladHttpWriteTransport {
  IoMoySkladHttpTransport({HttpClient Function()? clientFactory})
    : _clientFactory = clientFactory ?? HttpClient.new;

  final HttpClient Function() _clientFactory;

  @override
  Future<MoySkladHttpResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    required Object body,
    required Duration connectionTimeout,
    required Duration responseTimeout,
  }) async {
    final client = _clientFactory()
      ..connectionTimeout = connectionTimeout
      ..autoUncompress = true;
    try {
      final request = await client.postUrl(uri).timeout(connectionTimeout);
      headers.forEach(request.headers.set);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
      final response = await request.close().timeout(responseTimeout);
      final responseBody = await response
          .transform(utf8.decoder)
          .join()
          .timeout(responseTimeout);
      final responseHeaders = <String, String>{};
      response.headers.forEach((name, values) {
        responseHeaders[name.toLowerCase()] = values.join(',');
      });
      return MoySkladHttpResponse(
        statusCode: response.statusCode,
        body: responseBody,
        headers: responseHeaders,
      );
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<MoySkladHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration connectionTimeout,
    required Duration responseTimeout,
  }) async {
    final client = _clientFactory()
      ..connectionTimeout = connectionTimeout
      ..autoUncompress = true;
    try {
      final request = await client.getUrl(uri).timeout(connectionTimeout);
      headers.forEach(request.headers.set);
      final response = await request.close().timeout(responseTimeout);
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(responseTimeout);
      final responseHeaders = <String, String>{};
      response.headers.forEach((name, values) {
        responseHeaders[name.toLowerCase()] = values.join(',');
      });
      return MoySkladHttpResponse(
        statusCode: response.statusCode,
        body: body,
        headers: responseHeaders,
      );
    } finally {
      client.close(force: true);
    }
  }
}

class ApiResourceResult {
  const ApiResourceResult({
    required this.statusCode,
    this.data,
    this.retryAfter,
    this.errorCode,
    this.errorMessage,
    this.errorResponse,
  });
  final int statusCode;
  final Map<String, dynamic>? data;
  final Duration? retryAfter;
  final String? errorCode;
  final String? errorMessage;
  final Map<String, dynamic>? errorResponse;
  bool get isSuccess => statusCode >= 200 && statusCode < 300 && data != null;
  bool get isRetryable =>
      statusCode == 408 || statusCode == 429 || statusCode >= 500;
}

class MoySkladApiClient {
  MoySkladApiClient({
    MoySkladHttpTransport? transport,
    this.connectionTimeout = const Duration(seconds: 20),
    this.responseTimeout = const Duration(seconds: 30),
  }) : _transport = transport ?? IoMoySkladHttpTransport();

  static final Uri _inventoryListUri = Uri.https(
    'api.moysklad.ru',
    '/api/remap/1.2/entity/inventory',
    {'limit': '1', 'offset': '0', 'order': 'created,desc'},
  );

  final MoySkladHttpTransport _transport;
  final Duration connectionTimeout;
  final Duration responseTimeout;

  Future<ApiCheckResult> checkConnection(String? token) async {
    final normalizedToken = token?.trim();
    if (normalizedToken == null || normalizedToken.isEmpty) {
      return const ApiCheckResult(ApiCheckStatus.missingToken);
    }

    try {
      final response = await _transport.get(
        _inventoryListUri,
        connectionTimeout: connectionTimeout,
        responseTimeout: responseTimeout,
        headers: {
          HttpHeaders.authorizationHeader: 'Bearer $normalizedToken',
          HttpHeaders.acceptHeader: 'application/json;charset=utf-8',
          HttpHeaders.acceptEncodingHeader: 'gzip',
          HttpHeaders.userAgentHeader: 'LZakup Android app',
        },
      );

      if (response.statusCode == HttpStatus.ok) {
        try {
          final decoded = jsonDecode(response.body);
          if (decoded is Map<String, dynamic> && decoded['rows'] is List) {
            return const ApiCheckResult(ApiCheckStatus.connected);
          }
        } on FormatException {
          // A successful status without a valid inventory collection is not a valid check.
        }
        return const ApiCheckResult(
          ApiCheckStatus.invalidResponse,
          httpStatusCode: HttpStatus.ok,
        );
      }

      final apiError = _parseApiError(response.body);
      final authErrorCode = response.headers['x-lognex-auth'];
      final authErrorMessage = response.headers['x-lognex-auth-message'];
      if (response.statusCode == HttpStatus.unauthorized) {
        return ApiCheckResult(
          ApiCheckStatus.unauthorized,
          httpStatusCode: HttpStatus.unauthorized,
          apiErrorCode: apiError.$1,
          apiErrorMessage: apiError.$2,
          authErrorCode: authErrorCode,
          authErrorMessage: authErrorMessage,
        );
      }
      if (response.statusCode == HttpStatus.forbidden) {
        return ApiCheckResult(
          ApiCheckStatus.forbidden,
          httpStatusCode: HttpStatus.forbidden,
          apiErrorCode: apiError.$1,
          apiErrorMessage: apiError.$2,
          authErrorCode: authErrorCode,
          authErrorMessage: authErrorMessage,
        );
      }
      if (response.statusCode == HttpStatus.tooManyRequests) {
        return ApiCheckResult(
          ApiCheckStatus.rateLimited,
          httpStatusCode: HttpStatus.tooManyRequests,
          retryAfter: _parseRetryAfter(
            response.headers['retry-after'] ??
                response.headers['x-lognex-retry-after'],
          ),
          apiErrorCode: apiError.$1,
          apiErrorMessage: apiError.$2,
          authErrorCode: authErrorCode,
          authErrorMessage: authErrorMessage,
        );
      }
      return ApiCheckResult(
        ApiCheckStatus.unavailable,
        httpStatusCode: response.statusCode,
        apiErrorCode: apiError.$1,
        apiErrorMessage: apiError.$2,
        authErrorCode: authErrorCode,
        authErrorMessage: authErrorMessage,
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
    final relativePath = path.startsWith('/') ? path : '/$path';
    final normalizedPath = relativePath.startsWith('/api/remap/1.2/')
        ? relativePath
        : '/api/remap/1.2$relativePath';
    final uri = Uri.https('api.moysklad.ru', normalizedPath, query);
    try {
      final response = await _transport.get(
        uri,
        connectionTimeout: connectionTimeout,
        responseTimeout: responseTimeout,
        headers: {
          HttpHeaders.authorizationHeader: 'Bearer $normalized',
          HttpHeaders.acceptHeader: 'application/json;charset=utf-8',
          HttpHeaders.acceptEncodingHeader: 'gzip',
          HttpHeaders.userAgentHeader: 'LZakup Android app',
          'X-Lognex-Format-Metadata': 'true',
        },
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final apiError = _parseApiError(response.body);
        Map<String, dynamic>? errorResponse;
        try {
          final decoded = jsonDecode(response.body);
          if (decoded is Map) {
            errorResponse = Map<String, dynamic>.from(decoded);
          }
        } catch (_) {
          // Keep the HTTP status and parsed error code when the body is not JSON.
        }
        return ApiResourceResult(
          statusCode: response.statusCode,
          retryAfter: _parseRetryAfter(
            response.headers['retry-after'] ??
                response.headers['x-lognex-retry-after'],
          ),
          errorCode: apiError.$1?.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), ''),
          errorMessage: apiError.$2,
          errorResponse: errorResponse,
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

  Future<ApiResourceResult> postResource(
    String? token,
    String path,
    Object body,
  ) async {
    final normalized = token?.trim();
    if (normalized == null || normalized.isEmpty) {
      return const ApiResourceResult(
        statusCode: 401,
        errorCode: 'TOKEN_MISSING',
      );
    }
    final transport = _transport;
    if (transport is! MoySkladHttpWriteTransport) {
      return const ApiResourceResult(
        statusCode: 501,
        errorCode: 'WRITE_TRANSPORT_UNAVAILABLE',
      );
    }
    final writeTransport = transport as MoySkladHttpWriteTransport;
    final relativePath = path.startsWith('/') ? path : '/$path';
    final normalizedPath = relativePath.startsWith('/api/remap/1.2/')
        ? relativePath
        : '/api/remap/1.2$relativePath';
    final uri = Uri.https('api.moysklad.ru', normalizedPath);
    try {
      final response = await writeTransport.post(
        uri,
        body: body,
        connectionTimeout: connectionTimeout,
        responseTimeout: responseTimeout,
        headers: {
          HttpHeaders.authorizationHeader: 'Bearer $normalized',
          HttpHeaders.acceptHeader: 'application/json;charset=utf-8',
          HttpHeaders.acceptEncodingHeader: 'gzip',
          HttpHeaders.userAgentHeader: 'LZakup Android app',
          'X-Lognex-Format-Metadata': 'true',
        },
      );
      Map<String, dynamic>? decoded;
      try {
        final value = jsonDecode(response.body);
        if (value is Map) decoded = Map<String, dynamic>.from(value);
      } on FormatException {
        // The status code remains available for non-JSON error responses.
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final error = _parseApiError(response.body);
        return ApiResourceResult(
          statusCode: response.statusCode,
          retryAfter: _parseRetryAfter(
            response.headers['retry-after'] ??
                response.headers['x-lognex-retry-after'],
          ),
          errorCode: error.$1?.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), ''),
          errorMessage: error.$2,
          errorResponse: decoded,
        );
      }
      return ApiResourceResult(
        statusCode: response.statusCode,
        data: decoded,
        errorCode: decoded == null ? 'INVALID_JSON_OBJECT' : null,
      );
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

  (String?, String?) _parseApiError(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) return (null, null);
      final errors = decoded['errors'];
      if (errors is List && errors.isNotEmpty && errors.first is Map) {
        final error = errors.first as Map;
        final code = error['code']?.toString();
        final message =
            error['error_message']?.toString() ?? error['error']?.toString();
        return (code?.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), ''), message);
      }
      return (
        decoded['code']?.toString(),
        decoded['message']?.toString() ?? decoded['error']?.toString(),
      );
    } on FormatException {
      return (null, null);
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
