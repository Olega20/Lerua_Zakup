enum ApiCheckStatus {
  connected,
  missingToken,
  unauthorized,
  forbidden,
  rateLimited,
  timeout,
  invalidResponse,
  unavailable,
}

class ApiCheckResult {
  const ApiCheckResult(
    this.status, {
    this.httpStatusCode,
    this.retryAfter,
    this.apiErrorCode,
    this.apiErrorMessage,
    this.authErrorCode,
    this.authErrorMessage,
  });

  final ApiCheckStatus status;
  final int? httpStatusCode;
  final Duration? retryAfter;
  final String? apiErrorCode;
  final String? apiErrorMessage;
  final String? authErrorCode;
  final String? authErrorMessage;

  bool get isConnected => status == ApiCheckStatus.connected;
}
