import 'api_task.dart';

class ApiTaskExecutionException implements Exception {
  const ApiTaskExecutionException(
    this.status,
    this.response, {
    this.taskId,
    this.attemptNumber,
    this.httpStatusCode,
    this.safeErrorCode,
    this.safeErrorMessage,
  });

  final ApiTaskStatus status;
  final Map<String, Object?>? response;
  final int? taskId;
  final int? attemptNumber;
  final int? httpStatusCode;
  final String? safeErrorCode;
  final String? safeErrorMessage;

  @override
  String toString() {
    final message = safeErrorMessage;
    if (message != null && message.isNotEmpty) return message;
    final code = safeErrorCode;
    if (code != null && code.isNotEmpty)
      return 'API task ${status.name} ($code)';
    return 'API task completed with status ${status.name}';
  }
}
