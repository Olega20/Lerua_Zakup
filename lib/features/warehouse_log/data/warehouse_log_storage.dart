import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../domain/warehouse_log_entry.dart';

abstract interface class WarehouseLogStorage {
  Future<void> insert(WarehouseLogEntry entry, {required int limit});
  Future<List<WarehouseLogEntry>> latest({required int limit});
  Future<void> clear();
}

class SqfliteWarehouseLogStorage implements WarehouseLogStorage {
  SqfliteWarehouseLogStorage({
    DatabaseFactory? databaseFactory,
    String? databasePath,
  }) : _factory = databaseFactory ?? sqflite.databaseFactory,
       _databasePath = databasePath;

  final DatabaseFactory _factory;
  final String? _databasePath;
  Future<Database>? _database;

  Future<Database> get _db => _database ??= _open();

  Future<Database> _open() async {
    final path =
        _databasePath ??
        p.join(await _factory.getDatabasesPath(), 'warehouse_log.db');
    return _factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (database, version) async {
          await database.execute('''
            CREATE TABLE warehouse_log (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              timestamp INTEGER NOT NULL,
              level TEXT NOT NULL,
              event_type TEXT NOT NULL,
              description TEXT NOT NULL,
              http_status_code INTEGER,
              api_error_code TEXT
            )
          ''');
          await database.execute(
            'CREATE INDEX warehouse_log_timestamp_idx '
            'ON warehouse_log(timestamp DESC, id DESC)',
          );
        },
      ),
    );
  }

  @override
  Future<void> insert(
    WarehouseLogEntry entry, {
    required int limit,
  }) async {
    final database = await _db;
    await database.transaction((transaction) async {
      await transaction.insert('warehouse_log', {
        'timestamp': entry.timestamp.millisecondsSinceEpoch,
        'level': entry.level.name,
        'event_type': entry.type.name,
        'description': entry.description,
        'http_status_code': entry.httpStatusCode,
        'api_error_code': _safeApiCode(entry.apiErrorCode),
      });
      await transaction.rawDelete(
        'DELETE FROM warehouse_log WHERE id NOT IN '
        '(SELECT id FROM warehouse_log ORDER BY id DESC LIMIT ?)',
        [limit],
      );
    });
  }

  @override
  Future<List<WarehouseLogEntry>> latest({required int limit}) async {
    final database = await _db;
    final rows = await database.query(
      'warehouse_log',
      orderBy: 'timestamp DESC, id DESC',
      limit: limit,
    );
    return rows.map(_fromRow).toList(growable: false);
  }

  @override
  Future<void> clear() async {
    final database = await _db;
    await database.delete('warehouse_log');
  }

  Future<void> close() async {
    final databaseFuture = _database;
    _database = null;
    if (databaseFuture != null) {
      await (await databaseFuture).close();
    }
  }

  WarehouseLogEntry _fromRow(Map<String, Object?> row) => WarehouseLogEntry(
    id: row['id'] as int,
    timestamp: DateTime.fromMillisecondsSinceEpoch(row['timestamp'] as int),
    level: WarehouseLogLevel.values.byName(row['level'] as String),
    type: WarehouseLogEventType.values.byName(row['event_type'] as String),
    description: row['description'] as String,
    httpStatusCode: row['http_status_code'] as int?,
    apiErrorCode: row['api_error_code'] as String?,
  );

  String? _safeApiCode(String? value) {
    if (value == null || value.isEmpty) return null;
    return RegExp(r'^[A-Za-z0-9_.-]{1,64}$').hasMatch(value) ? value : null;
  }
}
