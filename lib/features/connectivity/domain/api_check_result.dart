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
  });

  final ApiCheckStatus status;
  final int? httpStatusCode;
  final Duration? retryAfter;

  bool get isConnected => status == ApiCheckStatus.connected;
}
