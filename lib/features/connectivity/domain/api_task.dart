enum ApiTaskStatus {
  pending,
  running,
  retryWait,
  succeeded,
  failed,
  uncertain,
  cancelled,
}

class ApiTask {
  const ApiTask({
    required this.id,
    required this.uid,
    required this.type,
    required this.logicalQueue,
    required this.status,
    required this.fifoSequence,
    required this.request,
    required this.attemptsCount,
    required this.createdAt,
    required this.updatedAt,
    this.response,
    this.nextAttemptAt,
    this.startedAt,
    this.finishedAt,
  });

  final int id;
  final String uid;
  final String type;
  final String logicalQueue;
  final ApiTaskStatus status;
  final int fifoSequence;
  final Map<String, Object?> request;
  final Map<String, Object?>? response;
  final int attemptsCount;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? nextAttemptAt;
  final DateTime? startedAt;
  final DateTime? finishedAt;

  static ApiTaskStatus parseStatus(String value) => switch (value) {
    'pending' => ApiTaskStatus.pending,
    'running' => ApiTaskStatus.running,
    'retry_wait' => ApiTaskStatus.retryWait,
    'succeeded' => ApiTaskStatus.succeeded,
    'failed' => ApiTaskStatus.failed,
    'uncertain' => ApiTaskStatus.uncertain,
    'cancelled' => ApiTaskStatus.cancelled,
    _ => throw FormatException('Unknown API task status: $value'),
  };

  static String storeStatus(ApiTaskStatus value) => switch (value) {
    ApiTaskStatus.pending => 'pending',
    ApiTaskStatus.running => 'running',
    ApiTaskStatus.retryWait => 'retry_wait',
    ApiTaskStatus.succeeded => 'succeeded',
    ApiTaskStatus.failed => 'failed',
    ApiTaskStatus.uncertain => 'uncertain',
    ApiTaskStatus.cancelled => 'cancelled',
  };
}

class ApiTaskClaim {
  const ApiTaskClaim({required this.task, required this.attemptNumber});
  final ApiTask task;
  final int attemptNumber;
}
