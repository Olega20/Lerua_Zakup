import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../../core/storage/app_database.dart';
import '../../../core/diagnostics/emergency_diagnostic_sink.dart';
import '../../warehouse_log/data/warehouse_log_repository.dart';
import '../../warehouse_log/domain/warehouse_log_entry.dart';

class PreparedOperationResult {
  const PreparedOperationResult({
    required this.operationId,
    required this.journalEntryId,
  });
  final int operationId;
  final int journalEntryId;
}

/// Common atomic operation/journal foundation. Concrete document workflows
/// are added only after the first operation type is selected.
class WarehouseJournalRepository {
  WarehouseJournalRepository({required this.database, this.warehouseLog});
  final AppDatabase database;
  final WarehouseLogRepository? warehouseLog;
  Future<Database> get _db => database.database;

  Future<void> _recordError(String component, Object error) async {
    try {
      if (warehouseLog == null) {
        await EmergencyDiagnosticSink.record(component, error);
      } else {
        await warehouseLog!.append(
          WarehouseLogEntry(
            timestamp: DateTime.now(),
            level: WarehouseLogLevel.error,
            type: error is DatabaseException
                ? WarehouseLogEventType.databaseError
                : WarehouseLogEventType.unexpectedError,
            description:
                'Не удалось сохранить складскую операцию или запись Журнала.',
            component: component,
            errorCode: error is DatabaseException
                ? 'DATABASE_WRITE_FAILED'
                : 'OPERATION_SAVE_FAILED',
            recommendedAction: 'Проверьте свободное место и состояние базы данных; повторите после проверки.',
            technicalDetails: error.runtimeType.toString(),
          ),
        );
      }
    } catch (journalError) {
      await EmergencyDiagnosticSink.record('$component.journal', journalError);
    }
  }

  Future<void> _writeLines(
    Transaction txn,
    int operationId,
    List<Map<String, Object?>> lines,
  ) async {
    await txn.delete(
      'business_operation_lines',
      where: 'operation_id = ?',
      whereArgs: [operationId],
    );
    for (final line in lines) {
      await txn.insert('business_operation_lines', {
        'operation_id': operationId,
        'product_id': line['product_id'],
        'product_moysklad_id_snapshot': line['product_moysklad_id'] ?? '',
        'product_name_snapshot': line['product_name'] ?? '',
        'quantity': line['quantity'] ?? 0,
        'uom_name_snapshot': line['uom_name'] ?? 'Не указано',
      });
    }
  }

  Future<int> saveDraft({
    required String operationUid,
    required String operationType,
    required int? supplierId,
    required String? organizationMoyskladId,
    required String? organizationName,
    required int? paymentMethodId,
    required String? paymentMethodName,
    required List<Map<String, Object?>> lines,
    Map<String, Object?> payload = const {},
  }) async {
    final db = await _db, now = DateTime.now().millisecondsSinceEpoch;
    final snapshot = <String, Object?>{
      'supplier_id': supplierId,
      'organization_moysklad_id': organizationMoyskladId,
      'organization_name': organizationName,
      'payment_method_id': paymentMethodId,
      'payment_method_name': paymentMethodName,
    };
    try {
      return await db.transaction((txn) async {
        final existing = await txn.query(
          'business_operations',
          where: 'operation_uid = ?',
          whereArgs: [operationUid],
          limit: 1,
        );
        int id;
        if (existing.isEmpty) {
          id = await txn.insert('business_operations', {
            'operation_uid': operationUid,
            'operation_type': operationType,
            'business_status': 'draft',
            'supplier_id': supplierId,
            'organization_moysklad_id_snapshot': organizationMoyskladId,
            'organization_name_snapshot': organizationName,
            'payment_method_id_snapshot': paymentMethodId,
            'payment_method_name_snapshot': paymentMethodName,
            'payload_json': jsonEncode({...payload, 'snapshot': snapshot}),
            'created_at': now,
            'updated_at': now,
          });
        } else {
          id = existing.first['id'] as int;
          final journal = await txn.query(
            'warehouse_journal_entries',
            where: 'operation_id = ?',
            whereArgs: [id],
            limit: 1,
          );
          if (journal.isNotEmpty) {
            throw StateError(
              'Подготовленную операцию нельзя вернуть в черновик',
            );
          }
          await txn.update(
            'business_operations',
            {
              'business_status': 'draft',
              'supplier_id': supplierId,
              'organization_moysklad_id_snapshot': organizationMoyskladId,
              'organization_name_snapshot': organizationName,
              'payment_method_id_snapshot': paymentMethodId,
              'payment_method_name_snapshot': paymentMethodName,
              'payload_json': jsonEncode({...payload, 'snapshot': snapshot}),
              'updated_at': now,
            },
            where: 'id = ?',
            whereArgs: [id],
          );
        }
        await _writeLines(txn, id, lines);
        return id;
      });
    } catch (error) {
      await _recordError('Сохранение черновика', error);
      rethrow;
    }
  }

  Future<PreparedOperationResult> createPreparedOperation({
    required String operationUid,
    required String operationType,
    required String summary,
    required int? supplierId,
    required String? organizationMoyskladId,
    required String? organizationName,
    required int? paymentMethodId,
    required String? paymentMethodName,
    required List<Map<String, Object?>> lines,
    Map<String, Object?> payload = const {},
  }) async {
    final db = await _db, now = DateTime.now().millisecondsSinceEpoch;
    try {
      return await db.transaction((txn) async {
        final snapshot = <String, Object?>{
          'supplier_id': supplierId,
          'organization_moysklad_id': organizationMoyskladId,
          'organization_name': organizationName,
          'payment_method_id': paymentMethodId,
          'payment_method_name': paymentMethodName,
        };
        final existing = await txn.query(
          'business_operations',
          where: 'operation_uid = ?',
          whereArgs: [operationUid],
          limit: 1,
        );
        int operationId;
        if (existing.isNotEmpty) {
          operationId = existing.first['id'] as int;
          final journal = await txn.query(
            'warehouse_journal_entries',
            where: 'operation_id = ?',
            whereArgs: [operationId],
            limit: 1,
          );
          if (journal.isNotEmpty) {
            return PreparedOperationResult(
              operationId: operationId,
              journalEntryId: journal.first['id'] as int,
            );
          }
          await txn.update(
            'business_operations',
            {
              'operation_type': operationType,
              'business_status': 'prepared',
              'supplier_id': supplierId,
              'organization_moysklad_id_snapshot': organizationMoyskladId,
              'organization_name_snapshot': organizationName,
              'payment_method_id_snapshot': paymentMethodId,
              'payment_method_name_snapshot': paymentMethodName,
              'payload_json': jsonEncode({...payload, 'snapshot': snapshot}),
              'updated_at': now,
            },
            where: 'id = ?',
            whereArgs: [operationId],
          );
        } else {
          operationId = await txn.insert('business_operations', {
            'operation_uid': operationUid,
            'operation_type': operationType,
            'business_status': 'prepared',
            'supplier_id': supplierId,
            'organization_moysklad_id_snapshot': organizationMoyskladId,
            'organization_name_snapshot': organizationName,
            'payment_method_id_snapshot': paymentMethodId,
            'payment_method_name_snapshot': paymentMethodName,
            'payload_json': jsonEncode({...payload, 'snapshot': snapshot}),
            'created_at': now,
            'updated_at': now,
          });
        }
        await _writeLines(txn, operationId, lines);
        final journalId = await txn.insert('warehouse_journal_entries', {
          'entry_uid': 'operation:$operationUid',
          'entry_type': operationType,
          'operation_id': operationId,
          'state': 'prepared',
          'summary': summary,
          'snapshot_json': jsonEncode(snapshot),
          'created_at': now,
          'updated_at': now,
        });
        await txn.insert('warehouse_journal_events', {
          'journal_entry_id': journalId,
          'event_type': 'intent_created',
          'to_state': 'intent',
          'level': 'info',
          'message': 'Создано намерение выполнить операцию',
          'details_json': jsonEncode(snapshot),
          'created_at': now,
        });
        await txn.insert('warehouse_journal_events', {
          'journal_entry_id': journalId,
          'event_type': 'local_saved',
          'from_state': 'intent',
          'to_state': 'prepared',
          'level': 'info',
          'message': 'Операция и её реквизиты сохранены локально',
          'details_json': jsonEncode({'line_count': lines.length}),
          'created_at': now,
        });
        return PreparedOperationResult(
          operationId: operationId,
          journalEntryId: journalId,
        );
      });
    } catch (error) {
      await _recordError('Подготовка операции', error);
      rethrow;
    }
  }

  Future<void> setOperationStatus(
    int operationId,
    String status, {
    String? message,
  }) async {
    const allowed = {
      'draft',
      'prepared',
      'queued',
      'sending',
      'succeeded',
      'failed',
      'cancelled',
    };
    if (!allowed.contains(status)) throw ArgumentError.value(status);
    final db = await _db, now = DateTime.now().millisecondsSinceEpoch;
    try {
      await db.transaction((txn) async {
        final rows = await txn.query(
          'business_operations',
          where: 'id = ?',
          whereArgs: [operationId],
          limit: 1,
        );
        if (rows.isEmpty) throw StateError('Операция не найдена');
        await txn.update(
          'business_operations',
          {'business_status': status, 'updated_at': now},
          where: 'id = ?',
          whereArgs: [operationId],
        );
        final journal = await txn.query(
          'warehouse_journal_entries',
          where: 'operation_id = ?',
          whereArgs: [operationId],
          limit: 1,
        );
        if (journal.isEmpty) throw StateError('Запись Журнала не найдена');
        await txn.update(
          'warehouse_journal_entries',
          {'state': status, 'updated_at': now},
          where: 'id = ?',
          whereArgs: [journal.first['id']],
        );
        await txn.insert('warehouse_journal_events', {
          'journal_entry_id': journal.first['id'],
          'event_type': 'status_changed',
          'from_state': rows.first['business_status'],
          'to_state': status,
          'level': status == 'failed' ? 'error' : 'info',
          'message': message ?? 'Статус операции изменён: $status',
          'created_at': now,
        });
      });
    } catch (error) {
      await _recordError('Изменение статуса операции', error);
      rethrow;
    }
  }

  Future<void> recordInventoryEvent({
    required String entryUid,
    required String summary,
    required String state,
    required String eventType,
    required String message,
    Map<String, Object?> snapshot = const {},
    String level = 'info',
  }) async {
    final db = await _db;
    final now = DateTime.now().millisecondsSinceEpoch;
    try {
      await db.transaction((txn) async {
        final existing = await txn.query(
          'warehouse_journal_entries',
          where: 'entry_uid = ?',
          whereArgs: [entryUid],
          limit: 1,
        );
        int journalId;
        String? previousState;
        if (existing.isEmpty) {
          journalId = await txn.insert('warehouse_journal_entries', {
            'entry_uid': entryUid,
            'entry_type': 'inventory',
            'operation_id': null,
            'state': state,
            'summary': summary,
            'snapshot_json': jsonEncode(snapshot),
            'created_at': now,
            'updated_at': now,
          });
        } else {
          journalId = existing.first['id'] as int;
          previousState = existing.first['state']?.toString();
          await txn.update(
            'warehouse_journal_entries',
            {
              'state': state,
              'summary': summary,
              'snapshot_json': jsonEncode(snapshot),
              'updated_at': now,
            },
            where: 'id = ?',
            whereArgs: [journalId],
          );
        }
        await txn.insert('warehouse_journal_events', {
          'journal_entry_id': journalId,
          'event_type': eventType,
          'from_state': previousState,
          'to_state': state,
          'level': level,
          'message': message,
          'details_json': jsonEncode(snapshot),
          'created_at': now,
        });
      });
    } catch (error) {
      await _recordError('Запись события инвентаризации в Журнал', error);
      rethrow;
    }
  }

  Future<List<Map<String, Object?>>> latestEntries({int limit = 300}) async {
    final db = await _db;
    return db.query(
      'warehouse_journal_entries',
      orderBy: 'created_at DESC,id DESC',
      limit: limit,
    );
  }

  Future<List<Map<String, Object?>>> events(int journalEntryId) async {
    final db = await _db;
    return db.query(
      'warehouse_journal_events',
      where: 'journal_entry_id = ?',
      whereArgs: [journalEntryId],
      orderBy: 'created_at,id',
    );
  }
}
