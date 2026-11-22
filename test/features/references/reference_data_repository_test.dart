import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lerua_zakup/core/storage/app_database.dart';
import 'package:lerua_zakup/core/storage/secure_token_store.dart';
import 'package:lerua_zakup/features/connectivity/data/api_task_dispatcher.dart';
import 'package:lerua_zakup/features/connectivity/data/api_task_repository.dart';
import 'package:lerua_zakup/features/connectivity/data/moysklad_api_client.dart';
import 'package:lerua_zakup/features/references/data/reference_data_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _TokenStore implements SecureTokenStore {
  @override
  Future<String?> readToken() async => null;
  @override
  Future<void> writeToken(String value) async {}
  @override
  Future<void> deleteToken() async {}
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
  List<Map<String, dynamic>> organizationRows = [];
  @override
  Future<Map<String, Object?>> requestGet({
    required String uid,
    required String type,
    required String logicalQueue,
    required String path,
    Map<String, String> query = const {},
    Duration timeout = const Duration(minutes: 3),
  }) async {
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
            'uom': {'name': 'шт'},
            'meta': {
              'href':
                  'https://api.moysklad.ru/api/remap/1.2/entity/product/p-1',
            },
          },
        ],
        'meta': {'size': 1},
      };
    }
    if (path == '/entity/organization') {
      return {
        'rows': organizationRows,
        'meta': {'size': organizationRows.length},
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
  late ReferenceDataRepository repository;
  setUp(() async {
    db = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    api = _FakeApi(db);
    repository = ReferenceDataRepository(database: db, api: api);
    final sql = await db.database;
    await sql.insert('warehouses', {'moysklad_id': 'w-1', 'name': 'Склад 1'});
    await sql.insert('warehouses', {'moysklad_id': 'w-2', 'name': 'Склад 2'});
  });
  tearDown(() async {
    await db.close();
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
