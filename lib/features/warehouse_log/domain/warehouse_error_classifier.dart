import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';

import '../domain/warehouse_log_entry.dart';

class WarehouseErrorDescription {
  const WarehouseErrorDescription({
    required this.type,
    required this.code,
    required this.message,
    required this.recommendedAction,
    required this.technicalDetails,
  });

  final WarehouseLogEventType type;
  final String code;
  final String message;
  final String recommendedAction;
  final String technicalDetails;
}

/// Converts exceptions into safe, actionable diagnostics. Raw exception
/// messages are deliberately excluded because they may contain credentials.
class WarehouseErrorClassifier {
  const WarehouseErrorClassifier();

  WarehouseErrorDescription describe(Object error) {
    if (error is TimeoutException) {
      return _result(
        'NETWORK_TIMEOUT',
        WarehouseLogEventType.timeout,
        'Превышено время ожидания ответа.',
        'Проверьте интернет и повторите действие.',
        error,
      );
    }
    if (error is SocketException) {
      return _result(
        'NETWORK_UNAVAILABLE',
        WarehouseLogEventType.apiUnavailable,
        'Не удалось установить сетевое соединение.',
        'Проверьте подключение к интернету.',
        error,
      );
    }
    if (error is DatabaseException) {
      return _result(
        'LOCAL_DATABASE_ERROR',
        WarehouseLogEventType.databaseError,
        'Не удалось прочитать или сохранить локальные данные.',
        'Не продолжайте повторные изменения. Откройте Журнал и проверьте состояние данных.',
        error,
      );
    }
    if (error is FormatException) {
      return _result(
        'INVALID_DATA_FORMAT',
        WarehouseLogEventType.invalidResponse,
        'Получены данные в неожиданном формате.',
        'Повторите обновление. Если ошибка повторится, проверьте подробности записи.',
        error,
      );
    }
    if (error is PlatformException) {
      return WarehouseErrorDescription(
        type: WarehouseLogEventType.unexpectedError,
        code: 'PLATFORM_SERVICE_ERROR',
        message: 'Не удалось выполнить системную операцию устройства.',
        recommendedAction: 'Проверьте разрешения и доступность функции, затем повторите действие.',
        technicalDetails:
            'Системный код: ${error.code.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '')}',
      );
    }
    return _result(
      'UNEXPECTED_ERROR',
      WarehouseLogEventType.unexpectedError,
      'Произошла непредвиденная ошибка.',
      'Откройте подробности записи Журнала. Не повторяйте отправку, если результат операции неизвестен.',
      error,
    );
  }

  WarehouseErrorDescription _result(
    String code,
    WarehouseLogEventType type,
    String message,
    String action,
    Object error,
  ) => WarehouseErrorDescription(
    type: type,
    code: code,
    message: message,
    recommendedAction: action,
    technicalDetails: 'Тип исключения: ${error.runtimeType}',
  );
}
