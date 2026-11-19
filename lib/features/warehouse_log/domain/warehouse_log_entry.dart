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
  });

  final int? id;
  final DateTime timestamp;
  final WarehouseLogLevel level;
  final WarehouseLogEventType type;
  final String description;
  final int? httpStatusCode;
  final String? apiErrorCode;

  String toSafeText() {
    final date = timestamp.toLocal();
    final stamp =
        '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}:${date.second.toString().padLeft(2, '0')}';
    return [
      stamp,
      warehouseLogLevelLabel(level),
      warehouseLogEventLabel(type),
      description,
      if (httpStatusCode != null) 'HTTP: $httpStatusCode',
      if (apiErrorCode != null) 'Код: $apiErrorCode',
    ].join('\n');
  }
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
};
