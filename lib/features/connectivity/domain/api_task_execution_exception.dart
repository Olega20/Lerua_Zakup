import 'api_task.dart';

class ApiTaskExecutionException implements Exception {
  const ApiTaskExecutionException(this.status, this.response);
  final ApiTaskStatus status;
  final Map<String, Object?>? response;
  @override
  String toString() => 'API task completed with status ${status.name}';
}
