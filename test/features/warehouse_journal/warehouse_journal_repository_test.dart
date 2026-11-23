import 'package:flutter_test/flutter_test.dart';
import 'package:lerua_zakup/core/storage/app_database.dart';
import 'package:lerua_zakup/features/warehouse_journal/data/warehouse_journal_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  test('inventory journal keeps one entry and appends lifecycle events', () async {
    final database = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    try {
      final repo = WarehouseJournalRepository(database: database);
      await repo.recordInventoryEvent(
        entryUid: 'inventory:test-session',
        summary: 'Инвентаризация • Основной склад',
        state: 'draft',
        eventType: 'draft_created',
        message: 'Создан локальный черновик инвентаризации',
        snapshot: {'warehouse': 'Основной склад'},
      );
      await repo.recordInventoryEvent(
        entryUid: 'inventory:test-session',
        summary: 'Инвентаризация • Основной склад',
        state: 'in_moysklad',
        eventType: 'sent_to_moysklad',
        message: 'Инвентаризация создана в МойСклад',
        snapshot: {'moysklad_inventory_id': 'inventory-1'},
      );

      final entries = await repo.latestEntries();
      expect(entries, hasLength(1));
      expect(entries.single['state'], 'in_moysklad');
      final events = await repo.events(entries.single['id'] as int);
      expect(events, hasLength(2));
      expect(events.first['event_type'], 'draft_created');
      expect(events.last['event_type'], 'sent_to_moysklad');
    } finally {
      await database.close();
    }
  });
  test(
    'draft autosave creates no journal entry until operation is prepared',
    () async {
      final database = AppDatabase(
        databaseFactory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      try {
        final db = await database.database;
        final supplierId = await db.insert('suppliers', {
          'moysklad_id': 'supplier-draft',
          'name': 'Поставщик',
        });
        final productId = await db.insert('products', {
          'moysklad_id': 'product-draft',
          'name': 'Саморез',
          'kind': 'product',
          'stock': 0,
          'uom_name': 'шт',
          'relevance_status': 'relevant',
          'is_archived': 0,
          'is_present': 1,
        });
        final repo = WarehouseJournalRepository(database: database);
        final draftId = await repo.saveDraft(
          operationUid: 'draft-uid',
          operationType: 'purchase',
          supplierId: supplierId,
          organizationMoyskladId: 'org-before',
          organizationName: 'Старая организация',
          paymentMethodId: 1,
          paymentMethodName: 'Старый способ',
          lines: [
            {
              'product_id': productId,
              'product_moysklad_id': 'product-draft',
              'product_name': 'Саморез',
              'quantity': 2,
            },
          ],
        );
        expect(await repo.latestEntries(), isEmpty);
        final prepared = await repo.createPreparedOperation(
          operationUid: 'draft-uid',
          operationType: 'purchase',
          summary: 'Закупка',
          supplierId: supplierId,
          organizationMoyskladId: 'org-current',
          organizationName: 'Текущая организация',
          paymentMethodId: 2,
          paymentMethodName: 'Текущий способ',
          lines: [
            {
              'product_id': productId,
              'product_moysklad_id': 'product-draft',
              'product_name': 'Саморез',
              'quantity': 4,
            },
          ],
        );
        expect(prepared.operationId, draftId);
        final operation = (await db.query(
          'business_operations',
          where: 'id=?',
          whereArgs: [draftId],
        )).single;
        expect(operation['business_status'], 'prepared');
        expect(operation['organization_moysklad_id_snapshot'], 'org-current');
        expect(operation['payment_method_name_snapshot'], 'Текущий способ');
        final line = (await db.query(
          'business_operation_lines',
          where: 'operation_id=?',
          whereArgs: [draftId],
        )).single;
        expect(line['quantity'], 4);
        expect(await repo.latestEntries(), hasLength(1));
      } finally {
        await database.close();
      }
    },
  );

  test('prepared operation, snapshots and both journal stages are saved atomically and idempotently', () async {
    final database = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    try {
      final db = await database.database;
      final supplierId = await db.insert('suppliers', {
        'moysklad_id': 'supplier-1',
        'name': 'Поставщик',
      });
      final productId = await db.insert('products', {
        'moysklad_id': 'product-1',
        'name': 'Шуруп',
        'kind': 'product',
        'stock': 0,
        'uom_name': 'шт',
        'relevance_status': 'relevant',
        'is_archived': 0,
        'is_present': 1,
      });
      final repo = WarehouseJournalRepository(database: database);
      final args = {
        'operationUid': 'op-unique-1',
        'operationType': 'purchase',
        'summary': 'Закупка • Поставщик',
        'supplierId': supplierId,
        'organizationMoyskladId': 'org-1',
        'organizationName': 'ООО Ромашка',
        'paymentMethodId': 17,
        'paymentMethodName': 'Безналичный расчёт',
        'lines': [
          {
            'product_id': productId,
            'product_moysklad_id': 'product-1',
            'product_name': 'Шуруп',
            'quantity': 10,
            'uom_name': 'шт',
          },
          {
            'product_id': productId,
            'product_moysklad_id': 'product-1',
            'product_name': 'Шуруп',
            'quantity': 5,
            'uom_name': 'шт',
          },
        ],
        'payload': {'note': 'Тест'},
      };
      final first = await repo.createPreparedOperation(
        operationUid: args['operationUid'] as String,
        operationType: args['operationType'] as String,
        summary: args['summary'] as String,
        supplierId: supplierId,
        organizationMoyskladId: args['organizationMoyskladId'] as String,
        organizationName: args['organizationName'] as String,
        paymentMethodId: 17,
        paymentMethodName: args['paymentMethodName'] as String,
        lines: args['lines'] as List<Map<String, Object?>>,
        payload: args['payload'] as Map<String, Object?>,
      );
      final second = await repo.createPreparedOperation(
        operationUid: 'op-unique-1',
        operationType: 'purchase',
        summary: 'Повтор',
        supplierId: supplierId,
        organizationMoyskladId: 'org-2',
        organizationName: 'Новое имя',
        paymentMethodId: 99,
        paymentMethodName: 'Другая оплата',
        lines: [],
      );
      expect(second.operationId, first.operationId);
      expect(second.journalEntryId, first.journalEntryId);
      final operation = (await db.query(
        'business_operations',
        where: 'id=?',
        whereArgs: [first.operationId],
      )).single;
      expect(operation['organization_moysklad_id_snapshot'], 'org-1');
      expect(operation['organization_name_snapshot'], 'ООО Ромашка');
      expect(operation['payment_method_id_snapshot'], 17);
      expect(operation['payment_method_name_snapshot'], 'Безналичный расчёт');
      expect(
        await db.query(
          'business_operation_lines',
          where: 'operation_id=?',
          whereArgs: [first.operationId],
        ),
        hasLength(2),
      );
      expect(await repo.events(first.journalEntryId), hasLength(2));
      expect((await repo.latestEntries()).single['state'], 'prepared');
    } finally {
      await database.close();
    }
  });
}
