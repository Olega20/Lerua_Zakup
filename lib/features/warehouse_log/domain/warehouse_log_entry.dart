enum WarehouseLogLevel { info, warning, error }

enum WarehouseLogEventType {
  checkStarted,
  checkSucceeded,
  missingToken,
  unauthorized,
  forbidden,
  rateLimited,
  timeout,
  invalidResponse,
  apiUnavailable,
  internetLost,
  internetRestored,
  tokenSaved,
  tokenDeleted,
  databaseError,
  syncFailed,
  apiTaskFailed,
  apiTaskUncertain,
  unexpectedError,
}

class WarehouseLogEntry {
  const WarehouseLogEntry({
    this.id,
    required this.timestamp,
    required this.level,
    required this.type,
    required this.description,
    this.httpStatusCode,
    this.apiErrorCode,
    this.component,
    this.errorCode,
    this.recommendedAction,
    this.technicalDetails,
    this.correlationId,
    this.operationId,
    this.taskId,
    this.attemptNumber,
  });
  final int? id;
  final DateTime timestamp;
  final WarehouseLogLevel level;
  final WarehouseLogEventType type;
  final String description;
  final int? httpStatusCode;
  final String? apiErrorCode;
  final String? component;
  final String? errorCode;
  final String? recommendedAction;
  final String? technicalDetails;
  final String? correlationId;
  final String? operationId;
  final String? taskId;
  final int? attemptNumber;

  String toSafeText() {
    final date = timestamp.toLocal();
    final stamp =
        '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}:${date.second.toString().padLeft(2, '0')}';
    return [
      stamp,
      warehouseLogLevelLabel(level),
      warehouseLogEventLabel(type),
      sanitizeDiagnosticText(description),
      if (component != null) 'Компонент: ${sanitizeDiagnosticText(component!)}',
      if (errorCode != null)
        'Код ошибки: ${sanitizeDiagnosticText(errorCode!)}',
      if (httpStatusCode != null) 'HTTP: $httpStatusCode',
      if (apiErrorCode != null)
        'Код API: ${sanitizeDiagnosticText(apiErrorCode!)}',
      if (attemptNumber != null) 'Попытка: $attemptNumber',
      if (operationId != null)
        'Операция: ${sanitizeDiagnosticText(operationId!)}',
      if (taskId != null) 'Задача: ${sanitizeDiagnosticText(taskId!)}',
      if (correlationId != null)
        'Связь: ${sanitizeDiagnosticText(correlationId!)}',
      if (recommendedAction != null)
        'Что сделать: ${sanitizeDiagnosticText(recommendedAction!)}',
      if (technicalDetails != null)
        'Технические сведения: ${sanitizeDiagnosticText(technicalDetails!)}',
    ].join('\n');
  }
}

String sanitizeDiagnosticText(String value) {
  var safe = value
      .replaceAll(
        RegExp(
          r'(authorization\s*[:=]\s*bearer\s+)[^\s,;]+',
          caseSensitive: false,
        ),
        r'$1[СКРЫТО]',
      )
      .replaceAll(
        RegExp(r'(bearer\s+)[A-Za-z0-9._~+/=-]+', caseSensitive: false),
        r'$1[СКРЫТО]',
      )
      .replaceAll(
        RegExp(
          r'((?:access[-_ ]?)?token\s*[:=]\s*)[^\s,;]+',
          caseSensitive: false,
        ),
        r'$1[СКРЫТО]',
      );
  if (safe.length > 4000) safe = '${safe.substring(0, 4000)}…';
  return safe;
}

String warehouseLogLevelLabel(WarehouseLogLevel level) => switch (level) {
  WarehouseLogLevel.info => 'Информация',
  WarehouseLogLevel.warning => 'Предупреждение',
  WarehouseLogLevel.error => 'Ошибка',
};
String warehouseLogEventLabel(WarehouseLogEventType type) => switch (type) {
  WarehouseLogEventType.checkStarted => 'Проверка подключения',
  WarehouseLogEventType.checkSucceeded => 'Подключение подтверждено',
  WarehouseLogEventType.missingToken => 'Токен отсутствует',
  WarehouseLogEventType.unauthorized => 'Ошибка авторизации',
  WarehouseLogEventType.forbidden => 'Доступ запрещён',
  WarehouseLogEventType.rateLimited => 'Ограничение запросов API',
  WarehouseLogEventType.timeout => 'Превышено время ожидания',
  WarehouseLogEventType.invalidResponse => 'Некорректный ответ API',
  WarehouseLogEventType.apiUnavailable => 'МойСклад недоступен',
  WarehouseLogEventType.internetLost => 'Интернет отключён',
  WarehouseLogEventType.internetRestored => 'Интернет восстановлен',
  WarehouseLogEventType.tokenSaved => 'Токен сохранён',
  WarehouseLogEventType.tokenDeleted => 'Токен удалён',
  WarehouseLogEventType.databaseError => 'Ошибка локальной базы данных',
  WarehouseLogEventType.syncFailed => 'Ошибка обновления справочника',
  WarehouseLogEventType.apiTaskFailed => 'Ошибка API-задачи',
  WarehouseLogEventType.apiTaskUncertain => 'Неопределённый результат API',
  WarehouseLogEventType.unexpectedError => 'Непредвиденная ошибка',
};
