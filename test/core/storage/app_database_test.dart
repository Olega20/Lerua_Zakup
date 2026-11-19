import 'package:flutter_test/flutter_test.dart';
import 'package:lerua_zakup/core/storage/app_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  test('creates one database with all planned business modules', () async {
    final appDatabase = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    final db = await appDatabase.database;
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table'",
    );
    final names = rows.map((row) => row['name']).toSet();

    expect(names, containsAll([
      'products', 'warehouses', 'storage_locations', 'organizations',
      'payment_methods', 'suppliers', 'business_operations',
      'business_operation_lines', 'warehouse_journal_entries',
      'warehouse_journal_events', 'api_tasks', 'api_task_attempts',
      'api_task_events', 'api_queue_state', 'journal_api_task_links',
      'warehouse_log', 'sync_runs', 'app_settings',
    ]));

    final columns = await db.rawQuery('PRAGMA table_info(warehouse_log)');
    expect(columns.map((row) => row['name']), containsAll([
      'component', 'error_code', 'recommended_action', 'technical_details',
      'correlation_id', 'operation_id', 'task_id', 'attempt_number',
    ]));
    await appDatabase.close();
  });
}
