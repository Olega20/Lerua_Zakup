import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lerua_zakup/core/storage/app_database.dart';
import 'package:lerua_zakup/core/storage/secure_token_store.dart';
import 'package:lerua_zakup/features/connectivity/data/api_task_dispatcher.dart';
import 'package:lerua_zakup/features/connectivity/data/api_task_repository.dart';
import 'package:lerua_zakup/features/connectivity/domain/api_task.dart';
import 'package:lerua_zakup/features/connectivity/data/moysklad_api_client.dart';
import 'package:lerua_zakup/features/references/data/reference_data_repository.dart';
import 'package:lerua_zakup/features/warehouse_journal/data/warehouse_journal_repository.dart';
import 'package:lerua_zakup/features/references/presentation/reference_screens.dart';
import 'package:lerua_zakup/features/references/presentation/inventory_screens.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _TokenStore implements SecureTokenStore {
  @override
  Future<String?> readToken() async => 'test-token';
  @override
  Future<void> writeToken(String value) async {}
  @override
  Future<void> deleteToken() async {}
}

class _FakeDirectTransport
    implements MoySkladHttpTransport, MoySkladHttpWriteTransport {
  int calls = 0;
  Uri? lastUri;
  List<Map<String, dynamic>> inventoryRows = [];
  List<Map<String, dynamic>> inventoryPositionRows = [];

  @override
  Future<MoySkladHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration connectionTimeout,
    required Duration responseTimeout,
  }) async {
    calls++;
    lastUri = uri;
    if (uri.path.endsWith('/entity/inventory')) {
      return MoySkladHttpResponse(
        statusCode: 200,
        body: jsonEncode({
          'rows': inventoryRows,
          'meta': {'size': inventoryRows.length},
        }),
      );
    }
    if (uri.path.endsWith('/positions')) {
      return MoySkladHttpResponse(
        statusCode: 200,
        body: jsonEncode({
          'rows': inventoryPositionRows,
          'meta': {'size': inventoryPositionRows.length},
        }),
      );
    }
    return const MoySkladHttpResponse(
      statusCode: 200,
      body: '{"rows":[{"id":"direct-store-1","name":"Склад напрямую","archived":false}],"meta":{"size":1}}',
    );
  }

  Object? postedBody;
  Uri? postedUri;

  @override
  Future<MoySkladHttpResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    required Object body,
    required Duration connectionTimeout,
    required Duration responseTimeout,
  }) async {
    postedUri = uri;
    postedBody = body;
    return const MoySkladHttpResponse(
      statusCode: 201,
      body: '{"id":"created-inventory-1","meta":{"href":"https://api.moysklad.ru/api/remap/1.2/entity/inventory/created-inventory-1"}}',
    );
  }
}

class _FakeApi extends ApiTaskDispatcher {
  _FakeApi(AppDatabase db)
    : super(
        repository: ApiTaskRepository(database: db),
        apiClient: MoySkladApiClient(),
        tokenStore: _TokenStore(),
        internet: const Stream<bool>.empty(),
      );
  bool failService = false;
  bool omitProductUomName = false;
  int supplierSearchRequests = 0;
  int warehouseRequests = 0;
  List<Map<String, dynamic>> organizationRows = [];
  List<Map<String, dynamic>> stockByStoreRows = [];
  bool failStockByStore = false;
  int postRequests = 0;
  int putRequests = 0;
  Map<String, Object?>? postedBody;
  Map<String, Object?>? putBody;

  @override
  Future<Map<String, Object?>> requestPost({
    required String uid,
    required String type,
    required String logicalQueue,
    required String path,
    required Map<String, Object?> body,
    Duration timeout = const Duration(minutes: 3),
  }) async {
    postRequests++;
    postedBody = body;
    return {
      'id': 'created-inventory-1',
      'meta': {
        'href': 'https://api.moysklad.ru/api/remap/1.2/entity/inventory/created-inventory-1',
      },
    };
  }

  @override
  Future<Map<String, Object?>> requestPut({
    required String uid,
    required String type,
    required String logicalQueue,
    required String path,
    required Map<String, Object?> body,
    Duration timeout = const Duration(minutes: 3),
  }) async {
    putRequests++;
    putBody = body;
    return {'id': 'updated-position'};
  }

  @override
  Future<List<ApiTask>> listTasks({
    String? logicalQueue,
    Set<ApiTaskStatus>? statuses,
  }) async => [];

  @override
  Future<Map<String, Object?>> requestGet({
    required String uid,
    required String type,
    required String logicalQueue,
    required String path,
    Map<String, String> query = const {},
    Duration timeout = const Duration(minutes: 3),
  }) async {
    if (path == '/entity/store') warehouseRequests++;
    if (failService && path == '/entity/service') {
      throw StateError('network');
    }
    if (path == '/entity/product' && query['filter'] == 'archived=false') {
      return {
        'rows': [
          {
            'id': 'p-1',
            'name': 'Крепёж',
            'archived': false,
            'productType': 'GOOD',
            'uom': omitProductUomName
                ? {
                    'meta': {
                      'href': 'https://api.moysklad.ru/api/remap/1.2/entity/uom/uom-1',
                    },
                  }
                : {'name': '\u0448\u0442'},
            'meta': {
              'href':
                  'https://api.moysklad.ru/api/remap/1.2/entity/product/p-1',
            },
          },
        ],
        'meta': {'size': 1},
      };
    }
    if (path == '/entity/counterparty') {
      supplierSearchRequests++;
      return {
        'rows': [
          {
            'id': 'supplier-search-1',
            'name': '\u041f\u043e\u0441\u0442\u0430\u0432\u0449\u0438\u043a \u0442\u0435\u0441\u0442\u043e\u0432\u044b\u0439',
            'phone': '123',
          },
        ],
        'meta': {'size': 1},
      };
    }
    if (path == '/entity/uom/uom-1') {
      return {'name': '\u0448\u0442'};
    }
    if (path == '/entity/organization') {
      return {
        'rows': organizationRows,
        'meta': {'size': organizationRows.length},
      };
    }
    if (path == '/report/stock/bystore') {
      if (failStockByStore) throw StateError('stock by store unavailable');
      return {
        'rows': stockByStoreRows,
        'meta': {'size': stockByStoreRows.length},
      };
    }
    if (path == '/report/stock/all') {
      return {
        'rows': [
          {
            'meta': {
              'href':
                  'https://api.moysklad.ru/api/remap/1.2/entity/product/p-1',
            },
            'quantity': 7,
          },
        ],
        'meta': {'size': 1},
      };
    }
    return {
      'rows': [],
      'meta': {'size': 0},
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late AppDatabase db;
  late _FakeApi api;
  late _FakeDirectTransport directTransport;
  late WarehouseJournalRepository journal;
  late ReferenceDataRepository repository;
  setUp(() async {
    db = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    api = _FakeApi(db);
    directTransport = _FakeDirectTransport();
    journal = WarehouseJournalRepository(database: db);
    repository = ReferenceDataRepository(
      database: db,
      api: api,
      directApiClient: MoySkladApiClient(transport: directTransport),
      tokenStore: _TokenStore(),
      warehouseJournal: journal,
    );
    final sql = await db.database;
    await sql.insert('warehouses', {'moysklad_id': 'w-1', 'name': 'Склад 1'});
    await sql.insert('warehouses', {'moysklad_id': 'w-2', 'name': 'Склад 2'});
  });
  tearDown(() async {
    await db.close();
  });

  test(
    'remote MoySklad inventories are fetched live and not stored locally',
    () async {
      directTransport.inventoryRows = [
        {
          'id': 'remote-inventory-1',
          'name': 'Пересчёт склада',
          'store': {'name': 'Склад 1'},
        },
      ];

      final remote = await repository.moySkladInventories();

      expect(remote.single['id'], 'remote-inventory-1');
      expect(await repository.inventorySessions(), isEmpty);
      expect(await api.listTasks(), isEmpty);
    },
  );

  test('remote inventory position updates use PUT and are journaled', () async {
    directTransport.inventoryPositionRows = [
      {
        'id': 'position-1',
        'quantity': 3,
        'assortment': {'name': 'Саморез'},
      },
    ];
    final positions = await repository.moySkladInventoryPositions(
      'remote-inventory-1',
    );
    expect(positions.single['id'], 'position-1');

    await repository.updateMoySkladInventoryPosition(
      inventoryId: 'remote-inventory-1',
      positionId: 'position-1',
      productName: 'Саморез',
      quantity: 8,
      documentName: 'Пересчёт склада',
    );

    expect(api.putRequests, 1);
    expect(api.putBody, {'quantity': 8.0});
    final entries = await journal.latestEntries();
    expect(entries.single['summary'], 'Пересчёт склада');
    expect(entries.single['state'], 'updated');
    final events = await journal.events(entries.single['id'] as int);
    expect(events.single['event_type'], 'position_updated');
  });

  test(
    'warehouse sync fetches directly without using the API task dispatcher',
    () async {
      await repository.syncWarehouses();

      expect(directTransport.calls, 1);
      expect(directTransport.lastUri!.path, '/api/remap/1.2/entity/store');
      expect(directTransport.lastUri!.queryParameters, {
        'limit': '100',
        'offset': '0',
        'filter': 'archived=false',
      });
      expect(api.warehouseRequests, 0);
      final warehouses = await repository.warehouses();
      expect(warehouses, hasLength(1));
      expect(warehouses.single['moysklad_id'], 'direct-store-1');
      expect(warehouses.single['name'], 'Склад напрямую');
    },
  );

  testWidgets('supplier search waits for typing to pause', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: SuppliersScreen(repository: repository)),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField),
      '\u0418\u043c\u043f\u0443\u043b',
    );
    await tester.pump(const Duration(milliseconds: 450));
    expect(api.supplierSearchRequests, 0);

    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(api.supplierSearchRequests, 1);
    expect(
      find.text(
        '\u041f\u043e\u0441\u0442\u0430\u0432\u0449\u0438\u043a \u0442\u0435\u0441\u0442\u043e\u0432\u044b\u0439',
      ),
      findsOneWidget,
    );
  });

  test('storage locations are local and unique case-insensitively within a warehouse', () async {
    final sql = await db.database;
    final w1 =
        (await sql.rawQuery(
              "SELECT id FROM warehouses WHERE moysklad_id='w-1'",
            )).single['id']
            as int;
    final w2 =
        (await sql.rawQuery(
              "SELECT id FROM warehouses WHERE moysklad_id='w-2'",
            )).single['id']
            as int;
    await repository.saveStorageLocation(w1, 'Стеллаж A');
    await expectLater(
      repository.saveStorageLocation(w1, 'стеллаж a'),
      throwsA(isA<StateError>()),
    );
    await repository.saveStorageLocation(w2, 'Стеллаж A');
    expect(await repository.storageLocations(w1), hasLength(1));
    expect(await repository.storageLocations(w2), hasLength(1));
  });

  test('product has one storage location per warehouse and location order is persisted', () async {
    final sql = await db.database;
    final product = await sql.insert('products', {
      'moysklad_id': 'storage-product',
      'name': 'Тестовый товар',
      'kind': 'product',
    });
    final warehouse = await sql.insert('warehouses', {
      'moysklad_id': 'storage-warehouse',
      'name': 'Склад тест',
    });
    await repository.saveStorageLocation(warehouse, 'Стеллаж 1');
    await repository.saveStorageLocation(warehouse, 'Стеллаж 2');
    final locations = await repository.storageLocations(warehouse);
    final first = locations[0]['id'] as int;
    final second = locations[1]['id'] as int;

    await repository.assignProductsToStorageLocation(
      [product],
      warehouse,
      first,
    );
    await repository.assignProductsToStorageLocation(
      [product],
      warehouse,
      second,
    );
    var assignments = await repository.productStorageAssignments(product);
    expect(assignments, hasLength(1));
    expect(assignments.single['storage_location_id'], second);

    await repository.reorderStorageLocations(warehouse, [second, first]);
    final reordered = await repository.storageLocations(warehouse);
    expect(reordered.map((r) => r['id']).toList(), [second, first]);
  });

  test('assigning a supplier to products saves a current local supplier and supports warehouse filtering', () async {
    final sql = await db.database;
    final productId = await sql.insert('products', {
      'moysklad_id': 'supplier-product',
      'name': 'Товар с поставщиком',
      'kind': 'product',
    });
    await sql.insert('warehouses', {
      'moysklad_id': 'supplier-warehouse',
      'name': 'Склад для фильтра',
    });
    await sql.insert('product_warehouse_stock', {
      'product_id': productId,
      'warehouse_moysklad_id': 'supplier-warehouse',
      'warehouse_name': 'Склад для фильтра',
      'stock': 7,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    });

    final supplier = {
      'id': 'supplier-from-search',
      'name': 'Поставщик из поиска',
      'phone': '+70000000000',
      'meta': {
        'href': 'https://api.moysklad.ru/api/remap/1.2/entity/counterparty/supplier-from-search',
      },
    };
    await repository.assignSupplierToProducts([productId], supplier);

    final assigned = await repository.productSupplier(productId);
    expect(assigned?['name'], 'Поставщик из поиска');
    expect(assigned?['phone'], '+70000000000');
    expect(assigned?['raw_sync_json'], isNotNull);
    expect(
      (await repository.suppliers(status: 'current')).single['moysklad_id'],
      'supplier-from-search',
    );
    expect(
      (await repository.products()).single['supplier_name'],
      'Поставщик из поиска',
    );
    expect(
      (await repository.products(warehouseMoyskladId: 'supplier-warehouse'))
          .single['id'],
      productId,
    );
    expect(
      await repository.products(warehouseMoyskladId: 'missing-warehouse'),
      isEmpty,
    );
    expect(await repository.productSupplier(productId), isNotNull);
  });

  test('inventory draft snapshots only assigned products and persists counts and skipped decisions', () async {
    final sql = await db.database;
    final organizationId = await sql.insert('organizations', {
      'moysklad_id': 'inventory-org',
      'name': 'Организация для инвентаризации',
    });
    final warehouseId =
        (await sql.query(
              'warehouses',
              where: 'moysklad_id=?',
              whereArgs: ['w-1'],
              limit: 1,
            )).single['id']
            as int;
    await repository.saveStorageLocation(warehouseId, 'Зона А');
    final locationId =
        (await repository.storageLocations(warehouseId)).single['id'] as int;
    final product1 = await sql.insert('products', {
      'moysklad_id': 'inventory-product-1',
      'name': 'Товар первый',
      'kind': 'product',
      'uom_name': 'шт',
    });
    final product2 = await sql.insert('products', {
      'moysklad_id': 'inventory-product-2',
      'name': 'Товар второй',
      'kind': 'product',
      'uom_name': 'шт',
    });
    await repository.assignProductsToStorageLocation(
      [product1, product2],
      warehouseId,
      locationId,
    );
    await sql.insert('product_warehouse_stock', {
      'product_id': product1,
      'warehouse_moysklad_id': 'w-1',
      'warehouse_name': 'Склад 1',
      'stock': 7,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    });

    final sessionId = await repository.createInventoryDraft(
      organizationId: organizationId,
      warehouseId: warehouseId,
      storageLocationIds: [locationId],
    );
    var lines = await repository.inventoryLines(sessionId);
    expect(lines, hasLength(2));
    final stockLine = lines.singleWhere(
      (line) => line['product_name_snapshot'] == 'Товар первый',
    );
    final skippedLine = lines.singleWhere(
      (line) => line['product_name_snapshot'] == 'Товар второй',
    );
    expect(stockLine['expected_stock'], 7);
    expect(
      lines.map((line) => line['product_name_snapshot']),
      containsAll(['Товар первый', 'Товар второй']),
    );

    await repository.saveInventoryCount(stockLine['id'] as int, 5);
    await repository.resolveSkippedInventoryLines(
      sessionId,
      zeroLineIds: {skippedLine['id'] as int},
    );
    lines = await repository.inventoryLines(sessionId);
    final savedLine = lines.singleWhere(
      (line) => line['product_name_snapshot'] == 'Товар первый',
    );
    final zeroLine = lines.singleWhere(
      (line) => line['product_name_snapshot'] == 'Товар второй',
    );
    expect(savedLine['actual_quantity'], 5);
    expect(zeroLine['actual_quantity'], 0);
    expect(zeroLine['include_in_inventory'], 1);
    expect((await repository.inventorySessions()).single['status'], 'draft');
    var journalEntries = await journal.latestEntries();
    expect(journalEntries.single['summary'], 'Инвентаризация • Склад 1');
    var journalEvents = await journal.events(
      journalEntries.single['id'] as int,
    );
    expect(journalEvents.single['event_type'], 'draft_created');

    await repository.deleteInventoryDraft(sessionId);
    expect(await repository.inventorySessions(), isEmpty);
    expect(await repository.inventoryLines(sessionId), isEmpty);
    journalEntries = await journal.latestEntries();
    expect(journalEntries.single['state'], 'cancelled');
    journalEvents = await journal.events(journalEntries.single['id'] as int);
    expect(journalEvents.last['event_type'], 'draft_deleted');
  });

  testWidgets(
    'inventory keypad saves counts and list mode remains switchable',
    (tester) async {
      final sql = await db.database;
      final organizationId = await sql.insert('organizations', {
        'moysklad_id': 'inventory-ui-org',
        'name': 'Организация UI',
      });
      final warehouseId =
          (await sql.query(
                'warehouses',
                where: 'moysklad_id=?',
                whereArgs: ['w-1'],
                limit: 1,
              )).single['id']
              as int;
      await repository.saveStorageLocation(warehouseId, 'Зона UI');
      final locationId =
          (await repository.storageLocations(warehouseId)).single['id'] as int;
      final productId = await sql.insert('products', {
        'moysklad_id': 'inventory-ui-product',
        'name': 'Товар UI',
        'kind': 'product',
        'uom_name': 'шт',
      });
      await repository.assignProductsToStorageLocation(
        [productId],
        warehouseId,
        locationId,
      );
      final sessionId = await repository.createInventoryDraft(
        organizationId: organizationId,
        warehouseId: warehouseId,
        storageLocationIds: [locationId],
      );

      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(
          home: InventorySessionScreen(
            repository: repository,
            sessionId: sessionId,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, '1').first);
      await tester.pumpAndSettle();
      expect(
        (await repository.inventoryLines(sessionId)).single['actual_quantity'],
        1,
      );

      await tester.tap(find.byTooltip('Список товаров'));
      await tester.pumpAndSettle();
      expect(find.text('Товар UI'), findsOneWidget);
      expect(find.textContaining('Факт: 1 шт'), findsOneWidget);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
    },
  );

  test('sends the completed local inventory to MoySklad and stores its document id', () async {
    final sql = await db.database;
    final organizationId = await sql.insert('organizations', {
      'moysklad_id': 'inventory-org',
      'name': 'Организация',
    });
    final warehouseId =
        (await sql.query(
              'warehouses',
              where: 'moysklad_id=?',
              whereArgs: ['w-1'],
              limit: 1,
            )).single['id']
            as int;
    await repository.saveStorageLocation(warehouseId, 'Зона');
    final locationId =
        (await repository.storageLocations(warehouseId)).single['id'] as int;
    final productId = await sql.insert('products', {
      'moysklad_id': 'inventory-product',
      'name': 'Товар для отправки',
      'kind': 'product',
      'uom_name': 'шт',
    });
    await repository.assignProductsToStorageLocation(
      [productId],
      warehouseId,
      locationId,
    );
    final sessionId = await repository.createInventoryDraft(
      organizationId: organizationId,
      warehouseId: warehouseId,
      storageLocationIds: [locationId],
    );
    final line = (await repository.inventoryLines(sessionId)).single;
    await repository.saveInventoryCount(line['id'] as int, 4);
    await repository.syncInventorySession(sessionId);

    expect(api.postRequests, 1);
    final payload = api.postedBody!;
    expect(payload['name'], '');
    expect(payload['externalCode'], isA<String>());
    expect(
      payload['syncId'],
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
    expect(
      (payload['organization'] as Map)['meta']['href'],
      contains('/entity/organization/inventory-org'),
    );
    expect(
      (payload['store'] as Map)['meta']['href'],
      contains('/entity/store/w-1'),
    );
    final positions = payload['positions'] as List;
    expect(positions, hasLength(1));
    expect(positions.single['quantity'], 4.0);
    expect(api.putRequests, 1);
    expect(
      api.putBody,
      isEmpty,
    );
    expect(
      (await repository.inventorySessions()).single['status'],
      'completed',
    );
    expect(
      (await repository.inventorySessions()).single['moysklad_id'],
      'created-inventory-1',
    );
    final entries = await journal.latestEntries();
    expect(entries.single['state'], 'in_moysklad');
    final events = await journal.events(entries.single['id'] as int);
    expect(events.map((event) => event['event_type']), [
      'draft_created',
      'sent_to_moysklad',
    ]);
  });

  test('payment method belongs to at most one organization and suppliers may share it', () async {
    final sql = await db.database;
    final o1 = await sql.insert('organizations', {
      'moysklad_id': 'o-1',
      'name': 'Организация 1',
    });
    final o2 = await sql.insert('organizations', {
      'moysklad_id': 'o-2',
      'name': 'Организация 2',
    });
    await repository.savePaymentMethod('Безнал');
    final method = (await repository.paymentMethods()).single['id'] as int;
    await repository.assignPaymentMethod(o1, method);
    await repository.assignPaymentMethod(o2, method);
    expect((await repository.paymentMethods()).single['organization_id'], o2);
    final s1 = await sql.insert('suppliers', {
      'moysklad_id': 's-1',
      'name': 'Поставщик 1',
    });
    final s2 = await sql.insert('suppliers', {
      'moysklad_id': 's-2',
      'name': 'Поставщик 2',
    });
    await repository.setSupplierPaymentMethod(s1, method);
    await repository.setSupplierPaymentMethod(s2, method);
    expect(
      (await repository.supplierPaymentDetails(s1)).single['organization_name'],
      'Организация 2',
    );
    expect(
      (await repository.supplierPaymentDetails(s2))
          .single['payment_method_name'],
      'Безнал',
    );
  });

  test(
    'supplier refresh preserves local identity, status and payment method',
    () async {
      final sql = await db.database;
      await sql.insert('organizations', {
        'moysklad_id': 'o-1',
        'name': 'Организация',
      });
      await repository.savePaymentMethod('Карта');
      final method = (await repository.paymentMethods()).single['id'] as int;
      await repository.openSupplierCard({
        'id': 's-1',
        'name': 'Старое имя',
        'phone': '111',
      });
      final first = (await repository.suppliers(status: 'other')).single;
      await repository.setSupplierStatus(first['id'] as int, 'current');
      await repository.setSupplierPaymentMethod(first['id'] as int, method);
      await repository.openSupplierCard({
        'id': 's-1',
        'name': 'Новое имя',
        'phone': '222',
      });
      final refreshed = (await repository.suppliers(status: 'current')).single;
      expect(refreshed['id'], first['id']);
      expect(refreshed['name'], 'Новое имя');
      expect(refreshed['phone'], '222');
      expect(refreshed['payment_method_id'], method);
    },
  );

  test(
    'product refresh resolves a missing UOM name from its metadata link',
    () async {
      api.omitProductUomName = true;

      await repository.syncProducts();

      final products = await repository.products();
      expect(products.single['uom_name'], '\u0448\u0442');
    },
  );

  test(
    'warehouse overview combines stock rows and local storage-only assignments',
    () async {
      final sql = await db.database;
      final productWithStock = await sql.insert('products', {
        'moysklad_id': 'overview-stock-product',
        'name': 'Товар с остатком',
        'kind': 'product',
      });
      final productWithAssignment = await sql.insert('products', {
        'moysklad_id': 'overview-assigned-product',
        'name': 'Товар только с местом',
        'kind': 'product',
      });
      final warehouse1 = await sql.insert('warehouses', {
        'moysklad_id': 'overview-w-1',
        'name': 'Склад Остатки',
      });
      final warehouse2 = await sql.insert('warehouses', {
        'moysklad_id': 'overview-w-2',
        'name': 'Склад Без отчёта',
      });
      await repository.saveStorageLocation(warehouse1, 'Стеллаж А');
      await repository.saveStorageLocation(warehouse2, 'Зона Б');
      final location1 =
          (await repository.storageLocations(warehouse1)).single['id'] as int;
      final location2 =
          (await repository.storageLocations(warehouse2)).single['id'] as int;
      await sql.insert('product_warehouse_stock', {
        'product_id': productWithStock,
        'warehouse_moysklad_id': 'overview-w-1',
        'warehouse_name': 'Склад Остатки',
        'stock': 12,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });
      await repository.assignProductsToStorageLocation(
        [productWithStock],
        warehouse1,
        location1,
      );
      await repository.assignProductsToStorageLocation(
        [productWithAssignment],
        warehouse2,
        location2,
      );
      // A balance at a second warehouse must not be shown when the product
      // has a local storage assignment only at the first warehouse.
      await sql.insert('product_warehouse_stock', {
        'product_id': productWithStock,
        'warehouse_moysklad_id': 'overview-w-2',
        'warehouse_name': 'Склад Без назначения',
        'stock': 99,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });

      expect(
        (await repository.products(warehouseMoyskladId: 'overview-w-1'))
            .map((row) => row['id'])
            .toList(),
        [productWithStock],
      );
      expect(
        (await repository.products(warehouseMoyskladId: 'overview-w-2'))
            .map((row) => row['id']),
        [productWithAssignment],
      );
      expect(
        await repository.products(warehouseMoyskladId: 'unknown-warehouse'),
        isEmpty,
      );

      final overview = await repository.productWarehouseOverview([
        productWithStock,
        productWithAssignment,
      ]);
      expect(overview, hasLength(2));
      final withStock = overview.singleWhere(
        (row) => row['product_id'] == productWithStock,
      );
      expect(withStock['warehouse_name'], 'Склад Остатки');
      expect(withStock['location_name'], 'Стеллаж А');
      expect(withStock['stock'], 12);
      final assignmentOnly = overview.singleWhere(
        (row) => row['product_id'] == productWithAssignment,
      );
      expect(assignmentOnly['warehouse_name'], 'Склад Без отчёта');
      expect(assignmentOnly['location_name'], 'Зона Б');
      expect(assignmentOnly['stock'], isNull);
      expect(await repository.productWarehouseOverview([]), isEmpty);
    },
  );

  test('product refresh stores per-warehouse stock and keeps the last snapshot if the report fails', () async {
    api.stockByStoreRows = [
      {
        'meta': {
          'href': 'https://api.moysklad.ru/api/remap/1.2/entity/product/p-1',
        },
        'stockByStore': [
          {
            'meta': {
              'href': 'https://api.moysklad.ru/api/remap/1.2/entity/store/w-1',
            },
            'name': 'Склад 1',
            'stock': 4,
          },
          {
            'meta': {
              'href': 'https://api.moysklad.ru/api/remap/1.2/entity/store/w-2',
            },
            'name': 'Склад 2',
            'stock': 3,
          },
        ],
      },
    ];
    await repository.syncProducts();
    final product = (await repository.products()).single;
    var stocks = await repository.productWarehouseStocks(product['id'] as int);
    expect(stocks, hasLength(2));
    expect(stocks.map((row) => row['stock']).toList(), [4, 3]);
    expect(stocks.map((row) => row['warehouse_moysklad_id']).toList(), [
      'w-1',
      'w-2',
    ]);

    api.failStockByStore = true;
    await repository.syncProducts();
    stocks = await repository.productWarehouseStocks(product['id'] as int);
    expect(stocks, hasLength(2));
  });

  test(
    'product refresh applies stock and status only after every page succeeds',
    () async {
      await repository.syncProducts();
      var products = await repository.products();
      expect(products.single['stock'], 7);
      expect(products.single['uom_name'], 'шт');
      await repository.setProductStatus([
        products.single['id'] as int,
      ], 'relevant');
      api.failService = true;
      await expectLater(repository.syncProducts(), throwsStateError);
      products = await repository.products();
      // Debug assertion also confirms that a failed page did not mark old rows absent.
      expect(products, hasLength(1));
      expect(products.single['relevance_status'], 'relevant');
      expect(products.single['is_present'], 1);
    },
  );
  test(
    'organization refresh stores records using the existing local schema',
    () async {
      api.organizationRows = [
        {'id': 'org-1', 'name': 'ООО Пример', 'archived': false},
      ];

      await repository.syncOrganizations();

      var organizations = await repository.organizations();
      expect(organizations, hasLength(1));
      expect(organizations.single['moysklad_id'], 'org-1');
      expect(organizations.single['name'], 'ООО Пример');

      api.organizationRows = [
        {'id': 'org-1', 'name': 'ООО Пример Новое', 'archived': false},
      ];
      await repository.syncOrganizations();

      organizations = await repository.organizations();
      expect(organizations, hasLength(1));
      expect(organizations.single['name'], 'ООО Пример Новое');
    },
  );
}
