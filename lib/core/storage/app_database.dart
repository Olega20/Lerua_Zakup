import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as sqflite;

/// Единственная SQLite-база приложения. Модули разделены таблицами и репозиториями.
class AppDatabase {
  AppDatabase({this.databaseFactory, this.databasePath});
  final sqflite.DatabaseFactory? databaseFactory;
  final String? databasePath;
  sqflite.DatabaseFactory get _factory => databaseFactory ?? sqflite.databaseFactory;
  Future<sqflite.Database>? _pending;
  Future<sqflite.Database> get database => _pending ??= _open();

  Future<sqflite.Database> _open() async {
    final path = databasePath ?? p.join(await _factory.getDatabasesPath(), 'lerua_zakup.db');
    final db = await _factory.openDatabase(path, options: sqflite.OpenDatabaseOptions(
      version: 1,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
        await db.execute('PRAGMA journal_mode = WAL');
      },
      onCreate: (db, version) async {
        for (final sql in _schema) { await db.execute(sql); }
        await db.insert('schema_migrations', {'version': version, 'applied_at': DateTime.now().millisecondsSinceEpoch});
      },
    ));
    if (databasePath == null) await _importLegacyLog(db);
    return db;
  }

  Future<void> _importLegacyLog(sqflite.Database target) async {
    const marker = 'legacy_warehouse_log_imported';
    if ((await target.query('app_settings', where: 'key = ?', whereArgs: [marker])).isNotEmpty) return;
    final oldPath = p.join(await _factory.getDatabasesPath(), 'warehouse_log.db');
    if (await _factory.databaseExists(oldPath)) {
      final old = await _factory.openDatabase(oldPath);
      try {
        final exists = await old.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name='warehouse_log'");
        if (exists.isNotEmpty) {
          final rows = await old.query('warehouse_log');
          await target.transaction((txn) async {
            for (final row in rows) {
              await txn.insert('warehouse_log', {
                'timestamp': row['timestamp'], 'level': row['level'], 'event_type': row['event_type'],
                'description': row['description'], 'http_status_code': row['http_status_code'],
                'api_error_code': row['api_error_code'],
              });
            }
          });
        }
      } finally { await old.close(); }
    }
    await target.insert('app_settings', {'key': marker, 'value': '1', 'updated_at': DateTime.now().millisecondsSinceEpoch});
  }

  Future<void> close() async {
    final value = _pending; _pending = null;
    if (value != null) await (await value).close();
  }

  static const _schema = <String>[
    'CREATE TABLE schema_migrations(version INTEGER PRIMARY KEY, applied_at INTEGER NOT NULL)',
    'CREATE TABLE app_settings(key TEXT PRIMARY KEY, value TEXT NOT NULL, updated_at INTEGER NOT NULL)',
    '''CREATE TABLE sync_runs(id INTEGER PRIMARY KEY AUTOINCREMENT, reference_type TEXT NOT NULL, started_at INTEGER NOT NULL, finished_at INTEGER, status TEXT NOT NULL, is_complete INTEGER NOT NULL DEFAULT 0, safe_error_code TEXT, safe_error_message TEXT)''',
    '''CREATE TABLE products(id INTEGER PRIMARY KEY AUTOINCREMENT, moysklad_id TEXT NOT NULL UNIQUE, name TEXT NOT NULL, kind TEXT NOT NULL CHECK(kind IN ('product','service')), stock REAL NOT NULL DEFAULT 0, uom_name TEXT NOT NULL DEFAULT 'Не указано', relevance_status TEXT NOT NULL DEFAULT 'unassigned' CHECK(relevance_status IN ('unassigned','relevant','irrelevant')), is_archived INTEGER NOT NULL DEFAULT 0, is_present INTEGER NOT NULL DEFAULT 1, last_synced_at INTEGER, raw_sync_json TEXT)''',
    'CREATE INDEX products_status_name_idx ON products(relevance_status, name COLLATE NOCASE)',
    '''CREATE TABLE warehouses(id INTEGER PRIMARY KEY AUTOINCREMENT, moysklad_id TEXT NOT NULL UNIQUE, name TEXT NOT NULL, is_archived INTEGER NOT NULL DEFAULT 0, is_present INTEGER NOT NULL DEFAULT 1, last_synced_at INTEGER, raw_sync_json TEXT)''',
    '''CREATE TABLE storage_locations(id INTEGER PRIMARY KEY AUTOINCREMENT, warehouse_id INTEGER NOT NULL REFERENCES warehouses(id) ON DELETE RESTRICT, name TEXT NOT NULL, sort_order INTEGER NOT NULL DEFAULT 0, is_active INTEGER NOT NULL DEFAULT 1, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, UNIQUE(warehouse_id,name))''',
    'CREATE INDEX storage_locations_order_idx ON storage_locations(warehouse_id,sort_order)',
    '''CREATE TABLE organizations(id INTEGER PRIMARY KEY AUTOINCREMENT, moysklad_id TEXT NOT NULL UNIQUE, name TEXT NOT NULL, is_archived INTEGER NOT NULL DEFAULT 0, is_present INTEGER NOT NULL DEFAULT 1, last_synced_at INTEGER, raw_sync_json TEXT)''',
    '''CREATE TABLE payment_methods(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL COLLATE NOCASE UNIQUE, organization_id INTEGER UNIQUE REFERENCES organizations(id) ON DELETE RESTRICT, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)''',
    '''CREATE TABLE suppliers(id INTEGER PRIMARY KEY AUTOINCREMENT, moysklad_id TEXT NOT NULL UNIQUE, name TEXT NOT NULL, phone TEXT, relevance_status TEXT NOT NULL DEFAULT 'other' CHECK(relevance_status IN ('current','other')), payment_method_id INTEGER REFERENCES payment_methods(id) ON DELETE RESTRICT, last_synced_at INTEGER, raw_sync_json TEXT)''',
    'CREATE INDEX suppliers_name_idx ON suppliers(name COLLATE NOCASE)',
    '''CREATE TABLE business_operations(id INTEGER PRIMARY KEY AUTOINCREMENT, operation_uid TEXT NOT NULL UNIQUE, operation_type TEXT NOT NULL, business_status TEXT NOT NULL, supplier_id INTEGER REFERENCES suppliers(id) ON DELETE RESTRICT, organization_moysklad_id_snapshot TEXT, organization_name_snapshot TEXT, payment_method_id_snapshot INTEGER, payment_method_name_snapshot TEXT, payload_json TEXT NOT NULL DEFAULT '{}', created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)''',
    '''CREATE TABLE business_operation_lines(id INTEGER PRIMARY KEY AUTOINCREMENT, operation_id INTEGER NOT NULL REFERENCES business_operations(id) ON DELETE CASCADE, product_id INTEGER REFERENCES products(id) ON DELETE RESTRICT, product_moysklad_id_snapshot TEXT NOT NULL, product_name_snapshot TEXT NOT NULL, quantity REAL NOT NULL, uom_name_snapshot TEXT NOT NULL)''',
    '''CREATE TABLE warehouse_journal_entries(id INTEGER PRIMARY KEY AUTOINCREMENT, entry_uid TEXT NOT NULL UNIQUE, entry_type TEXT NOT NULL, operation_id INTEGER REFERENCES business_operations(id) ON DELETE RESTRICT, state TEXT NOT NULL, summary TEXT NOT NULL, snapshot_json TEXT, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)''',
    '''CREATE TABLE warehouse_journal_events(id INTEGER PRIMARY KEY AUTOINCREMENT, journal_entry_id INTEGER NOT NULL REFERENCES warehouse_journal_entries(id) ON DELETE CASCADE, event_type TEXT NOT NULL, from_state TEXT, to_state TEXT, level TEXT NOT NULL DEFAULT 'info', message TEXT NOT NULL, details_json TEXT, created_at INTEGER NOT NULL)''',
    '''CREATE TABLE api_tasks(id INTEGER PRIMARY KEY AUTOINCREMENT, task_uid TEXT NOT NULL UNIQUE, task_type TEXT NOT NULL, logical_queue TEXT NOT NULL, status TEXT NOT NULL, fifo_sequence INTEGER NOT NULL, request_json TEXT, response_json TEXT, attempts_count INTEGER NOT NULL DEFAULT 0, next_attempt_at INTEGER, started_at INTEGER, finished_at INTEGER, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)''',
    'CREATE INDEX api_tasks_dispatch_idx ON api_tasks(status,fifo_sequence)',
    '''CREATE TABLE api_task_attempts(id INTEGER PRIMARY KEY AUTOINCREMENT, task_id INTEGER NOT NULL REFERENCES api_tasks(id) ON DELETE CASCADE, attempt_number INTEGER NOT NULL, started_at INTEGER NOT NULL, finished_at INTEGER, http_status_code INTEGER, outcome TEXT NOT NULL, safe_error_code TEXT, safe_error_message TEXT, response_excerpt TEXT, UNIQUE(task_id,attempt_number))''',
    '''CREATE TABLE api_task_events(id INTEGER PRIMARY KEY AUTOINCREMENT, task_id INTEGER NOT NULL REFERENCES api_tasks(id) ON DELETE CASCADE, event_type TEXT NOT NULL, from_state TEXT, to_state TEXT, message TEXT NOT NULL, created_at INTEGER NOT NULL)''',
    '''CREATE TABLE api_queue_state(logical_queue TEXT PRIMARY KEY, is_paused INTEGER NOT NULL DEFAULT 0, pause_reason TEXT, requires_resume_confirmation INTEGER NOT NULL DEFAULT 0, updated_at INTEGER NOT NULL)''',
    '''CREATE TABLE journal_api_task_links(journal_entry_id INTEGER NOT NULL REFERENCES warehouse_journal_entries(id) ON DELETE CASCADE, task_id INTEGER NOT NULL REFERENCES api_tasks(id) ON DELETE CASCADE, relation_type TEXT NOT NULL DEFAULT 'related', PRIMARY KEY(journal_entry_id,task_id))''',
    '''CREATE TABLE warehouse_log(id INTEGER PRIMARY KEY AUTOINCREMENT, timestamp INTEGER NOT NULL, level TEXT NOT NULL, event_type TEXT NOT NULL, description TEXT NOT NULL, http_status_code INTEGER, api_error_code TEXT)''',
    'CREATE INDEX warehouse_log_timestamp_idx ON warehouse_log(timestamp DESC,id DESC)',
  ];
}
