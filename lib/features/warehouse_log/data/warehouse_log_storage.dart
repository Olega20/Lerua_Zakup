import 'package:sqflite/sqflite.dart' as sqflite;

import '../../../core/storage/app_database.dart';
import '../domain/warehouse_log_entry.dart';

abstract interface class WarehouseLogStorage {
  Future<void> insert(WarehouseLogEntry entry, {required int limit});
  Future<List<WarehouseLogEntry>> latest({required int limit});
  Future<void> clear();
}

class SqfliteWarehouseLogStorage implements WarehouseLogStorage {
  SqfliteWarehouseLogStorage({
    this.databaseFactory,
    this.databasePath,
    AppDatabase? appDatabase,
  }) : _appDatabase = appDatabase ??
            AppDatabase(databaseFactory: databaseFactory, databasePath: databasePath);

  final sqflite.DatabaseFactory? databaseFactory;
  final String? databasePath;
  final AppDatabase _appDatabase;
  Future<sqflite.Database> get _db => _appDatabase.database;

  @override
  Future<void> insert(WarehouseLogEntry entry, {required int limit}) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.insert('warehouse_log', {
        'timestamp': entry.timestamp.millisecondsSinceEpoch,
        'level': entry.level.name,
        'event_type': entry.type.name,
        'description': entry.description,
        'http_status_code': entry.httpStatusCode,
        'api_error_code': _safeApiCode(entry.apiErrorCode),
        'component': entry.component == null ? null : sanitizeDiagnosticText(entry.component!),
        'error_code': entry.errorCode == null ? null : _safeApiCode(entry.errorCode),
        'recommended_action': entry.recommendedAction == null ? null : sanitizeDiagnosticText(entry.recommendedAction!),
        'technical_details': entry.technicalDetails == null ? null : sanitizeDiagnosticText(entry.technicalDetails!),
        'correlation_id': entry.correlationId,
        'operation_id': entry.operationId,
        'task_id': entry.taskId,
        'attempt_number': entry.attemptNumber,
      });
      await txn.rawDelete(
        'DELETE FROM warehouse_log WHERE id NOT IN '
        '(SELECT id FROM warehouse_log ORDER BY id DESC LIMIT ?)',
        [limit],
      );
    });
  }

  @override
  Future<List<WarehouseLogEntry>> latest({required int limit}) async {
    final db = await _db;
    final rows = await db.query(
      'warehouse_log',
      orderBy: 'timestamp DESC, id DESC',
      limit: limit,
    );
    return rows.map(_fromRow).toList(growable: false);
  }

  @override
  Future<void> clear() async {
    final db = await _db;
    await db.delete('warehouse_log');
  }

  Future<void> close() => _appDatabase.close();

  WarehouseLogEntry _fromRow(Map<String, Object?> row) => WarehouseLogEntry(
        id: row['id'] as int,
        timestamp: DateTime.fromMillisecondsSinceEpoch(row['timestamp'] as int),
        level: WarehouseLogLevel.values.byName(row['level'] as String),
        type: WarehouseLogEventType.values.byName(row['event_type'] as String),
        description: row['description'] as String,
        httpStatusCode: row['http_status_code'] as int?,
        apiErrorCode: row['api_error_code'] as String?,
        component: row['component'] as String?,
        errorCode: row['error_code'] as String?,
        recommendedAction: row['recommended_action'] as String?,
        technicalDetails: row['technical_details'] as String?,
        correlationId: row['correlation_id'] as String?,
        operationId: row['operation_id'] as String?,
        taskId: row['task_id'] as String?,
        attemptNumber: row['attempt_number'] as int?,
      );

  String? _safeApiCode(String? value) {
    if (value == null || value.isEmpty) return null;
    return RegExp(r'^[A-Za-z0-9_.-]{1,64}$').hasMatch(value) ? value : null;
  }
}
