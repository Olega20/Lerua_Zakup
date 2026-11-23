import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lerua_zakup/core/storage/app_database.dart';
import 'package:lerua_zakup/core/storage/secure_token_store.dart';
import 'package:lerua_zakup/features/connectivity/data/api_task_dispatcher.dart';
import 'package:lerua_zakup/features/connectivity/data/api_task_repository.dart';
import 'package:lerua_zakup/features/connectivity/data/moysklad_api_client.dart';
import 'package:lerua_zakup/features/references/data/reference_data_repository.dart';
import 'package:lerua_zakup/features/references/presentation/reference_screens.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _TokenStore implements SecureTokenStore {
  @override
  Future<String?> readToken() async => 'test-token';
  @override
  Future<void> writeToken(String value) async {}
  @override
  Future<void> deleteToken() async {}
}

class _FakeDirectTransport implements MoySkladHttpTransport {
  int calls = 0;
  Uri? lastUri;

  @override
  Future<MoySkladHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration connectionTimeout,
    required Duration responseTimeout,
  }) async {
    calls++;
    lastUri = uri;
    return const MoySkladHttpResponse(
      statusCode: 200,
      body: '{"rows":[{"id":"direct-store-1","name":"Склад напрямую","archived":false}],"meta":{"size":1}}',
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
  late ReferenceDataRepository repository;
  setUp(() async {
    db = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    api = _FakeApi(db);
    directTransport = _FakeDirectTransport();
    repository = ReferenceDataRepository(
      database: db,
      api: api,
      directApiClient: MoySkladApiClient(transport: directTransport),
      tokenStore: _TokenStore(),
    );
    final sql = await db.database;
    await sql.insert('warehouses', {'moysklad_id': 'w-1', 'name': 'Склад 1'});
    await sql.insert('warehouses', {'moysklad_id': 'w-2', 'name': 'Склад 2'});
  });
  tearDown(() async {
    await db.close();
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
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField),
      '\u0418\u043c\u043f\u0443\u043b',
    );
    await tester.pump(const Duration(milliseconds: 450));
    expect(api.supplierSearchRequests, 0);

    await tester.pump(const Duration(milliseconds: 100));
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

  test('warehouse overview combines stock rows and local storage-only assignments', () async {
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
    final location1 = (await repository.storageLocations(warehouse1)).single['id'] as int;
    final location2 = (await repository.storageLocations(warehouse2)).single['id'] as int;
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
  });

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
