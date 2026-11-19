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
