import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lerua_zakup/core/storage/app_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  test(
    'upgrades a version 4 database without losing existing products',
    () async {
      final directory = await Directory.systemTemp.createTemp('lerua-db-v4-');
      final path = '${directory.path}${Platform.pathSeparator}legacy.db';
      final oldDb = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 4,
          onCreate: (db, version) async {
            await db.execute(
              'CREATE TABLE schema_migrations(version INTEGER PRIMARY KEY, applied_at INTEGER NOT NULL)',
            );
            await db.execute(
              'CREATE TABLE products(id INTEGER PRIMARY KEY, moysklad_id TEXT NOT NULL, name TEXT NOT NULL)',
            );
            await db.execute(
              'CREATE TABLE suppliers(id INTEGER PRIMARY KEY, moysklad_id TEXT NOT NULL, name TEXT NOT NULL)',
            );
            await db.execute(
              'CREATE TABLE product_warehouse_stock(id INTEGER PRIMARY KEY, product_id INTEGER, warehouse_moysklad_id TEXT, warehouse_name TEXT, stock REAL, updated_at INTEGER)',
            );
            await db.insert('products', {
              'id': 41,
              'moysklad_id': 'existing-product',
              'name': 'Сохранённый товар',
            });
          },
        ),
      );
      await oldDb.close();

      final appDatabase = AppDatabase(
        databaseFactory: databaseFactoryFfi,
        databasePath: path,
      );
      final db = await appDatabase.database;
      final product = await db.query('products');
      final stockTable = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='product_warehouse_stock'",
      );
      final supplierTable = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='product_supplier_assignments'",
      );

      expect(product.single['moysklad_id'], 'existing-product');
      expect(stockTable, hasLength(1));
      expect(supplierTable, hasLength(1));
      await appDatabase.close();
      await directory.delete(recursive: true);
    },
  );

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

    expect(
      names,
      containsAll([
        'products',
        'product_warehouse_stock',
        'product_supplier_assignments',
        'warehouses',
        'storage_locations',
        'organizations',
        'payment_methods',
        'suppliers',
        'inventory_sessions',
        'inventory_lines',
        'business_operations',
        'business_operation_lines',
        'warehouse_journal_entries',
        'warehouse_journal_events',
        'api_tasks',
        'api_task_attempts',
        'api_task_events',
        'api_queue_state',
        'journal_api_task_links',
        'warehouse_log',
        'sync_runs',
        'app_settings',
      ]),
    );

    final columns = await db.rawQuery('PRAGMA table_info(warehouse_log)');
    expect(
      columns.map((row) => row['name']),
      containsAll([
        'component',
        'error_code',
        'recommended_action',
        'technical_details',
        'correlation_id',
        'operation_id',
        'task_id',
        'attempt_number',
      ]),
    );
    await appDatabase.close();
  });
}
