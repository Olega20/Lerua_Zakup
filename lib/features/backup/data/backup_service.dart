import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/storage/app_database.dart';
import '../../../core/diagnostics/emergency_diagnostic_sink.dart';
import '../../warehouse_log/data/warehouse_log_repository.dart';
import '../../warehouse_log/domain/warehouse_log_entry.dart';

class BackupService {
  BackupService({required this.database, this.warehouseLog});
  final AppDatabase database;
  final WarehouseLogRepository? warehouseLog;
  static const _channel = MethodChannel('lerua_zakup/platform');

  Future<void> _recordError(String component, Object error) async {
    try {
      if (warehouseLog == null) {
        await EmergencyDiagnosticSink.record(component, error);
      } else {
        await warehouseLog!.append(
          WarehouseLogEntry(
            timestamp: DateTime.now(),
            level: WarehouseLogLevel.error,
            type: WarehouseLogEventType.databaseError,
            description: 'Ошибка резервного копирования или экспорта данных.',
            component: component,
            errorCode: 'BACKUP_OPERATION_FAILED',
            recommendedAction: 'Проверьте доступ к выбранной папке и свободное место; выберите другое место хранения.',
            technicalDetails: error.runtimeType.toString(),
          ),
        );
      }
    } catch (journalError) {
      await EmergencyDiagnosticSink.record('$component.journal', journalError);
    }
  }

  Future<Database> get _db => database.database;

  Future<String?> folderUri() async {
    final rows = await (await _db).query(
      'app_settings',
      where: 'key = ?',
      whereArgs: ['backup_folder_uri'],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<void> chooseFolder() async {
    try {
      await _chooseFolderInternal();
    } catch (error) {
      await _recordError('Выбор папки резервного копирования', error);
      rethrow;
    }
  }

  Future<void> _chooseFolderInternal() async {
    final uri = await _channel.invokeMethod<String>('chooseBackupFolder');
    if (uri == null) return;
    final db = await _db;
    final previous = await folderUri();
    if (previous != uri) {
      await db.delete(
        'app_settings',
        where: 'key = ?',
        whereArgs: ['backup_last_success_at'],
      );
    }
    await db.insert('app_settings', {
      'key': 'backup_folder_uri',
      'value': uri,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<DateTime?> lastBackupAt() async {
    final rows = await (await _db).query(
      'app_settings',
      where: 'key = ?',
      whereArgs: ['backup_last_success_at'],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final value = int.tryParse(rows.first['value'] as String);
    return value == null ? null : DateTime.fromMillisecondsSinceEpoch(value);
  }

  Future<int> journalRetentionDays() async {
    final rows = await (await _db).query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: ['journal_retention_days'],
      limit: 1,
    );
    if (rows.isEmpty) return 30;
    final value = int.tryParse(rows.first['value'] as String);
    return value != null && value > 0 ? value : 30;
  }

  Future<void> setJournalRetentionDays(int days) async {
    if (days < 1 || days > 3650) throw ArgumentError.value(days);
    final now = DateTime.now().millisecondsSinceEpoch;
    await (await _db).insert('app_settings', {
      'key': 'journal_retention_days',
      'value': '$days',
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> ensureDailyBackup() async {
    final folder = await folderUri();
    if (folder == null) return;
    final last = await lastBackupAt();
    if (last != null &&
        DateTime.now().difference(last) < const Duration(hours: 24)) {
      return;
    }
    await createBackup();
  }

  Future<String> createBackup() async {
    try {
      return await _createBackupInternal();
    } catch (error) {
      await _recordError('Создание резервной копии', error);
      rethrow;
    }
  }

  Future<String> _createBackupInternal() async {
    final folder = await folderUri();
    if (folder == null) {
      throw StateError('Сначала выберите папку резервного копирования');
    }
    final db = await _db;
    final checkpoint = await db.rawQuery('PRAGMA wal_checkpoint(FULL)');
    final busy = checkpoint.isEmpty
        ? 0
        : (checkpoint.first.values.first as num?)?.toInt() ?? 0;
    if (busy != 0) {
      throw StateError(
        'База данных занята и не может быть безопасно скопирована',
      );
    }
    final path = await database.databaseFilePath;
    final bytes = await File(path).readAsBytes();
    final now = DateTime.now();
    final name =
        'lerua_zakup_${now.year.toString().padLeft(4, '0')}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}${now.millisecond.toString().padLeft(3, '0')}.db';
    final uri = await _channel.invokeMethod<String>('writeBackupFile', {
      'folderUri': folder,
      'fileName': name,
      'bytes': Uint8List.fromList(bytes),
    });
    if (uri == null) throw StateError('Не удалось сохранить резервную копию');
    await db.insert('app_settings', {
      'key': 'backup_last_success_at',
      'value': '${now.millisecondsSinceEpoch}',
      'updated_at': now.millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await _rotate(folder);
    await _pruneAfterBackup(now);
    return name;
  }

  Future<List<Map<String, dynamic>>> backups() async {
    final folder = await folderUri();
    if (folder == null) return [];
    final result = await _channel.invokeListMethod<dynamic>('listBackupFiles', {
      'folderUri': folder,
    });
    return (result ?? [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where(
          (e) =>
              (e['name'] as String? ?? '').startsWith('lerua_zakup_') &&
              (e['name'] as String).endsWith('.db'),
        )
        .toList()
      ..sort((a, b) => (b['modified'] as int).compareTo(a['modified'] as int));
  }

  Future<void> _rotate(String folder) async {
    final list = await backups();
    for (final item in list.skip(30)) {
      await _channel.invokeMethod<bool>('deleteBackupFile', {
        'uri': item['uri'],
      });
    }
  }

  Future<void> _pruneAfterBackup(DateTime now) async {
    final db = await _db;
    final retentionDays = await journalRetentionDays();
    final cutoff = now
        .subtract(Duration(days: retentionDays))
        .millisecondsSinceEpoch;
    await db.transaction((t) async {
      await t.delete(
        'warehouse_journal_entries',
        where: 'created_at < ?',
        whereArgs: [cutoff],
      );
      await t.delete(
        'api_tasks',
        where: "status IN ('succeeded','failed','cancelled') AND finished_at IS NOT NULL AND finished_at < ?",
        whereArgs: [cutoff],
      );
      await t.delete(
        'warehouse_log',
        where: 'timestamp < ?',
        whereArgs: [cutoff],
      );
    });
  }

  Future<void> exportData({
    required String table,
    required String format,
    DateTime? from,
    DateTime? to,
  }) async {
    try {
      await _exportDataInternal(
        table: table,
        format: format,
        from: from,
        to: to,
      );
    } catch (error) {
      await _recordError('Экспорт данных', error);
      rethrow;
    }
  }

  Future<void> _exportDataInternal({
    required String table,
    required String format,
    DateTime? from,
    DateTime? to,
  }) async {
    final allowed = <String>{
      'products',
      'warehouses',
      'organizations',
      'suppliers',
      'payment_methods',
      'warehouse_journal_entries',
      'api_tasks',
      'warehouse_log',
    };
    if (!allowed.contains(table)) throw ArgumentError.value(table);
    final folder = await folderUri();
    if (folder == null) throw StateError('Сначала выберите папку для экспорта');
    final db = await _db;
    final clauses = <String>[];
    final args = <Object?>[];
    final dateColumn = {
      'products': 'last_synced_at',
      'warehouses': 'last_synced_at',
      'organizations': 'last_synced_at',
      'suppliers': 'last_synced_at',
      'payment_methods': 'updated_at',
      'warehouse_journal_entries': 'created_at',
      'api_tasks': 'created_at',
      'warehouse_log': 'timestamp',
    }[table]!;
    if (from != null) {
      clauses.add('$dateColumn >= ?');
      args.add(from.millisecondsSinceEpoch);
    }
    if (to != null) {
      clauses.add('$dateColumn <= ?');
      args.add(
        to
            .add(const Duration(days: 1))
            .subtract(const Duration(milliseconds: 1))
            .millisecondsSinceEpoch,
      );
    }
    final rows = await db.query(
      table,
      where: clauses.isEmpty ? null : clauses.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: '$dateColumn DESC',
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    final extension = format == 'csv' ? 'csv' : 'json';
    final name = 'lerua_export_${table}_$now.$extension';
    final String output;
    if (extension == 'json') {
      output = jsonEncode(rows);
    } else {
      final columns = rows.isEmpty ? <String>[] : rows.first.keys.toList();
      String cell(Object? v) {
        final s = v?.toString() ?? '';
        return '"${s.replaceAll('"', '""')}"';
      }

      output = [
        columns.map(cell).join(','),
        ...rows.map((r) => columns.map((k) => cell(r[k])).join(',')),
      ].join('\r\n');
    }
    await _channel.invokeMethod<String>('writeBackupFile', {
      'folderUri': folder,
      'fileName': name,
      'bytes': Uint8List.fromList(utf8.encode(output)),
    });
  }

  Future<void> restoreSelectedBackup() async {
    try {
      await _restoreSelectedBackupInternal();
    } catch (error) {
      await _recordError('Восстановление базы данных', error);
      rethrow;
    }
  }

  Future<void> _restoreSelectedBackupInternal() async {
    final uri = await _channel.invokeMethod<String>('chooseBackupFile');
    if (uri == null) return;
    final bytes = await _channel.invokeMethod<Uint8List>('readBackupFile', {
      'uri': uri,
    });
    if (bytes == null || bytes.isEmpty) {
      throw const FormatException('Файл резервной копии пуст');
    }
    final temp = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}lerua_restore_check.db',
    );
    await temp.writeAsBytes(bytes, flush: true);
    final candidate = database.atPath(temp.path);
    final check = await candidate.database;
    try {
      final integrity = await check.rawQuery('PRAGMA integrity_check');
      if (integrity.isEmpty || integrity.first.values.first != 'ok') {
        throw const FormatException('Проверка целостности SQLite не пройдена');
      }
      final schema = await check.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='schema_migrations'",
      );
      if (schema.isEmpty) {
        throw const FormatException(
          'Файл не является резервной копией Lerua Zakup',
        );
      }
    } finally {
      await candidate.close();
    }
    await database.close();
    final target = await database.databaseFilePath;
    final backup = File('$target.pre_restore');
    final original = File(target);
    if (await original.exists()) await original.copy(backup.path);
    try {
      await temp.copy(target);
      await database.database;
      if (await backup.exists()) await backup.delete();
    } catch (_) {
      if (await backup.exists()) await backup.copy(target);
      rethrow;
    } finally {
      if (await temp.exists()) await temp.delete();
    }
  }
}
