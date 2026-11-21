import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../../core/storage/app_database.dart';
import '../../../core/diagnostics/emergency_diagnostic_sink.dart';
import '../../connectivity/data/api_task_dispatcher.dart';
import '../../connectivity/domain/api_task_execution_exception.dart';
import '../../warehouse_log/data/warehouse_log_repository.dart';
import '../../warehouse_log/domain/warehouse_log_entry.dart';

class ReferenceDataRepository {
  ReferenceDataRepository({
    required this.database,
    required this.api,
    this.warehouseLog,
  });
  final AppDatabase database;
  final ApiTaskDispatcher api;
  final WarehouseLogRepository? warehouseLog;
  Future<void>? _productSyncFuture;
  Future<Database> get _db => database.database;

  Future<T> _guard<T>(
    String component,
    String code,
    Future<T> Function() action,
  ) async {
    try {
      return await action();
    } catch (error) {
      await _recordError(component, code, error);
      rethrow;
    }
  }

  Future<void> _recordError(String component, String code, Object error) async {
    final apiError = error is ApiTaskExecutionException ? error : null;
    final errorCode = apiError?.safeErrorCode ??
        (apiError == null ? code : 'API_TASK_${apiError.status.name.toUpperCase()}');
    final details = <String>[
      'Тип исключения: ${error.runtimeType}',
      if (apiError?.taskId != null) 'Задача: ${apiError!.taskId}',
      if (apiError?.attemptNumber != null) 'Попытка: ${apiError!.attemptNumber}',
      if (apiError?.httpStatusCode != null) 'HTTP: ${apiError!.httpStatusCode}',
      if (apiError?.safeErrorCode != null) 'Код API: ${apiError!.safeErrorCode}',
      if (apiError?.safeErrorMessage != null) 'Сообщение API: ${apiError!.safeErrorMessage}',
      if (apiError?.response != null)
        'Фрагмент ответа API: ${jsonEncode(apiError!.response)}',
    ];
    final entry = WarehouseLogEntry(
      timestamp: DateTime.now(),
      level: WarehouseLogLevel.error,
      type: WarehouseLogEventType.syncFailed,
      description: 'Не удалось выполнить операцию справочника: $component.',
      component: component,
      errorCode: errorCode,
      httpStatusCode: apiError?.httpStatusCode,
      apiErrorCode: apiError?.safeErrorCode,
      taskId: apiError?.taskId?.toString(),
      attemptNumber: apiError?.attemptNumber,
      recommendedAction: apiError?.httpStatusCode == 403
          ? 'Проверьте права Access Token на чтение организаций в МойСклад.'
          : apiError?.httpStatusCode == 404
          ? 'Проверьте доступность endpoint организаций и версию API.'
          : 'Проверьте подробности ответа API и локальной базы данных; повторите действие после устранения причины.',
      technicalDetails: details.join('; '),
    );
    try {
      if (warehouseLog == null) {
        await EmergencyDiagnosticSink.record(component, error);
      } else {
        await warehouseLog!.append(entry);
      }
    } catch (journalError) {
      await EmergencyDiagnosticSink.record('$component.journal', journalError);
    }
  }

  Future<List<Map<String, dynamic>>> _all(
    String path,
    String type,
    String queue, {
    String? filter,
  }) async {
    const limit = 100;
    var offset = 0;
    final result = <Map<String, dynamic>>[];
    while (true) {
      final q = <String, String>{'limit': '$limit', 'offset': '$offset'};
      if (filter != null) q['filter'] = filter;
      final data = await api.requestGet(
        uid:
            '$type:${filter ?? 'all'}:$offset:${DateTime.now().microsecondsSinceEpoch}',
        type: 'reference_page',
        logicalQueue: queue,
        path: path,
        query: q,
      );
      final rows = data['rows'];
      if (rows is! List) {
        throw const FormatException('В ответе МойСклад отсутствует rows');
      }
      result.addAll(
        rows.whereType<Map>().map((e) => Map<String, dynamic>.from(e)),
      );
      final meta = data['meta'];
      final size = meta is Map ? (meta['size'] as num?)?.toInt() : null;
      if (rows.length < limit ||
          (size != null && offset + rows.length >= size)) {
        break;
      }
      offset += rows.length;
    }
    return result;
  }

  Future<DateTime?> lastProductSync() async {
    final r = await (await _db).query(
      'sync_runs',
      where: "reference_type='products' AND status='succeeded'",
      orderBy: 'finished_at DESC',
      limit: 1,
    );
    if (r.isEmpty || r.first['finished_at'] == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(r.first['finished_at'] as int);
  }

  Future<void> syncProducts() {
    final active = _productSyncFuture;
    if (active != null) return active;
    final future = _syncProductsInternal();
    _productSyncFuture = future;
    return future.whenComplete(() => _productSyncFuture = null);
  }

  Future<void> _syncProductsInternal() async {
    final db = await _db;
    await db.update('sync_runs', {
      'status': 'failed',
      'is_complete': 0,
      'safe_error_code': 'INTERRUPTED_BY_RESTART',
      'safe_error_message': 'Обновление было прервано закрытием приложения.',
    }, where: "reference_type = 'products' AND status = 'running'");
    final started = DateTime.now().millisecondsSinceEpoch;
    final run = await db.insert('sync_runs', {
      'reference_type': 'products',
      'started_at': started,
      'status': 'running',
    });
    try {
      final rows = <Map<String, dynamic>>[];
      for (final endpoint in ['/entity/product', '/entity/service']) {
        final localKind = endpoint.endsWith('/service') ? 'service' : 'product';
        for (final archived in [false, true]) {
          final fetched = await _all(
            endpoint,
            '${endpoint.split('/').last}_${archived ? 'archive' : 'active'}',
            'catalog',
            filter: 'archived=$archived',
          );
          rows.addAll(fetched.map((row) => {...row, '_local_kind': localKind}));
        }
      }
      final stockRows = await _all(
        '/report/stock/all',
        'product_stock',
        'catalog',
      );
      final stockById = <String, double>{};
      for (final stockRow in stockRows) {
        final meta = stockRow['meta'];
        final href = meta is Map ? meta['href']?.toString() : null;
        final id = href == null
            ? null
            : Uri.tryParse(href)?.pathSegments
                  .where((s) => s.isNotEmpty)
                  .lastOrNull;
        final quantity = (stockRow['quantity'] as num?)?.toDouble();
        if (id != null && quantity != null) stockById[id] = quantity;
      }
      final normalized = <Map<String, Object?>>[];
      for (final r in rows) {
        if ([
          'BUNDLE',
          'VARIANT',
        ].contains(r['productType']?.toString().toUpperCase())) {
          continue;
        }
        final id = r['id']?.toString(), name = r['name']?.toString().trim();
        if (id == null || name == null || name.isEmpty) continue;
        final uom = r['uom'];
        final service = r['_local_kind'] == 'service';
        normalized.add({
          'moysklad_id': id,
          'name': name,
          'kind': service ? 'service' : 'product',
          'stock': stockById[id] ?? (r['stock'] as num?)?.toDouble() ?? 0,
          'uom_name': uom is Map
              ? (uom['name']?.toString() ?? 'Не указано')
              : 'Не указано',
          'is_archived': r['archived'] == true ? 1 : 0,
          'raw_sync_json': jsonEncode(r),
        });
      }
      var unarchivedCount = 0;
      await db.transaction((t) async {
        await t.update('products', {'is_present': 0});
        for (final r in normalized) {
          final old = await t.query(
            'products',
            columns: ['id', 'relevance_status', 'is_archived'],
            where: 'moysklad_id=?',
            whereArgs: [r['moysklad_id']],
            limit: 1,
          );
          if (old.isNotEmpty &&
              old.first['is_archived'] == 1 &&
              r['is_archived'] == 0) {
            unarchivedCount++;
          }
          final values = {
            ...r,
            'is_present': 1,
            'last_synced_at': started,
            'relevance_status':
                r['is_archived'] == 1 ||
                    old.isEmpty ||
                    old.first['is_archived'] == 1
                ? 'unassigned'
                : old.first['relevance_status'],
          };
          if (old.isEmpty) {
            await t.insert('products', values);
          } else {
            await t.update(
              'products',
              values,
              where: 'id = ?',
              whereArgs: [old.first['id']],
            );
          }
        }
        await t.insert('app_settings', {
          'key': 'products_unarchived_count',
          'value': '$unarchivedCount',
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        await t.update(
          'sync_runs',
          {
            'finished_at': DateTime.now().millisecondsSinceEpoch,
            'status': 'succeeded',
            'is_complete': 1,
          },
          where: 'id=?',
          whereArgs: [run],
        );
      });
    } catch (error) {
      await _recordError('Синхронизация товаров', 'PRODUCT_SYNC_FAILED', error);
      await db.update(
        'sync_runs',
        {
          'finished_at': DateTime.now().millisecondsSinceEpoch,
          'status': 'failed',
          'is_complete': 0,
          'safe_error_code': 'PRODUCT_SYNC_FAILED',
          'safe_error_message':
              'Не удалось полностью загрузить каталог товаров.',
        },
        where: 'id=?',
        whereArgs: [run],
      );
      rethrow;
    }
  }

  Future<int> consumeUnarchivedProductCount() async {
    final db = await _db;
    final rows = await db.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: ['products_unarchived_count'],
      limit: 1,
    );
    final count = rows.isEmpty
        ? 0
        : int.tryParse(rows.first['value'] as String) ?? 0;
    await db.insert('app_settings', {
      'key': 'products_unarchived_count',
      'value': '0',
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    return count;
  }

  Future<List<Map<String, Object?>>> products({
    String search = '',
    String? status,
    bool archived = false,
  }) async {
    final clauses = <String>['is_archived=?', 'is_present=1'];
    final args = <Object?>[archived ? 1 : 0];
    if (status != null) {
      clauses.add('relevance_status=?');
      args.add(status);
    }
    if (search.trim().isNotEmpty) {
      clauses.add('name LIKE ?');
      args.add('%${search.trim()}%');
    }
    return (await _db).query(
      'products',
      where: clauses.join(' AND '),
      whereArgs: args,
      orderBy: "CASE relevance_status WHEN 'unassigned' THEN 0 WHEN 'relevant' THEN 1 ELSE 2 END,name COLLATE NOCASE",
    );
  }

  Future<Map<String, int>> productCounts() async {
    final rows = await (await _db).rawQuery(
      "SELECT relevance_status,COUNT(*) c FROM products WHERE is_archived=0 AND is_present=1 GROUP BY relevance_status",
    );
    final m = {'unassigned': 0, 'relevant': 0, 'irrelevant': 0};
    for (final r in rows) {
      m[r['relevance_status'] as String] = r['c'] as int;
    }
    return m;
  }

  Future<void> setProductStatus(Iterable<int> ids, String status) => _guard(
    'Изменение актуальности товаров',
    'PRODUCT_STATUS_SAVE_FAILED',
    () => _setProductStatus(ids, status),
  );

  Future<void> _setProductStatus(Iterable<int> ids, String status) async {
    if (!{'unassigned', 'relevant', 'irrelevant'}.contains(status)) {
      throw ArgumentError.value(status);
    }
    final db = await _db;
    await db.transaction((t) async {
      for (final id in ids.toSet()) {
        await t.update(
          'products',
          {'relevance_status': status},
          where: 'id=? AND is_archived=0',
          whereArgs: [id],
        );
      }
    });
  }

  Future<void> syncWarehouses() async {
    try {
      final rows = await _all(
        '/entity/store',
        'warehouses',
        'warehouses',
        filter: 'archived=false',
      );
      final db = await _db, now = DateTime.now().millisecondsSinceEpoch;
      await db.transaction((t) async {
        await t.update('warehouses', {'is_present': 0});
        for (final r in rows) {
          final id = r['id']?.toString(), name = r['name']?.toString();
          if (id == null || name == null) continue;
          final values = {
            'moysklad_id': id,
            'name': name,
            'is_archived': 0,
            'is_present': 1,
            'last_synced_at': now,
            'raw_sync_json': jsonEncode(r),
          };
          final old = await t.query(
            'warehouses',
            columns: ['id'],
            where: 'moysklad_id = ?',
            whereArgs: [id],
            limit: 1,
          );
          if (old.isEmpty) {
            await t.insert('warehouses', values);
          } else {
            await t.update(
              'warehouses',
              values,
              where: 'id = ?',
              whereArgs: [old.first['id']],
            );
          }
        }
      });
    } catch (error) {
      await _recordError(
        'Синхронизация складов',
        'WAREHOUSE_SYNC_FAILED',
        error,
      );
      rethrow;
    }
  }

  Future<List<Map<String, Object?>>> warehouses() => (_db.then(
    (d) => d.query(
      'warehouses',
      where: 'is_present=1 AND is_archived=0',
      orderBy: 'name COLLATE NOCASE',
    ),
  ));
  Future<List<Map<String, Object?>>> storageLocations(int warehouseId) =>
      (_db.then(
        (d) => d.query(
          'storage_locations',
          where: 'warehouse_id=? AND is_active=1',
          whereArgs: [warehouseId],
          orderBy: 'sort_order,name COLLATE NOCASE',
        ),
      ));
  Future<void> saveStorageLocation(int warehouseId, String name, {int? id}) =>
      _guard(
        'Сохранение места хранения',
        'STORAGE_LOCATION_SAVE_FAILED',
        () => _saveStorageLocation(warehouseId, name, id: id),
      );

  Future<void> _saveStorageLocation(
    int warehouseId,
    String name, {
    int? id,
  }) async {
    final n = name.trim();
    if (n.isEmpty) throw ArgumentError('Укажите название места хранения');
    final db = await _db, now = DateTime.now().millisecondsSinceEpoch;
    final existing = await db.query(
      'storage_locations',
      columns: ['id', 'name'],
      where: 'warehouse_id = ? AND is_active = 1',
      whereArgs: [warehouseId],
    );
    final duplicate = existing.any(
      (row) =>
          row['id'] != id &&
          (row['name'] as String).toLowerCase() == n.toLowerCase(),
    );
    if (duplicate) throw StateError('Такое место хранения уже существует');
    if (id == null) {
      await db.insert('storage_locations', {
        'warehouse_id': warehouseId,
        'name': n,
        'created_at': now,
        'updated_at': now,
      });
    } else {
      await db.update(
        'storage_locations',
        {'name': n, 'updated_at': now},
        where: 'id=? AND warehouse_id=?',
        whereArgs: [id, warehouseId],
      );
    }
  }

  Future<void> archiveStorageLocation(int id) => _db.then(
    (d) => d.update(
      'storage_locations',
      {'is_active': 0, 'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id=?',
      whereArgs: [id],
    ),
  );

  Future<void> syncOrganizations() async {
    try {
      final rows = await _all(
        '/entity/organization',
        'organizations',
        'organizations',
        filter: 'archived=false',
      );
      final db = await _db, now = DateTime.now().millisecondsSinceEpoch;
      await db.transaction((t) async {
        await t.update('organizations', {'is_present': 0});
        for (final r in rows) {
          final id = r['id']?.toString(), name = r['name']?.toString();
          if (id == null || name == null) continue;
          final values = {
            'moysklad_id': id,
            'name': name,
            'is_archived': 0,
            'is_present': 1,
            'last_synced_at': now,
            'raw_sync_json': jsonEncode(r),
          };
          final old = await t.query(
            'organizations',
            columns: ['id'],
            where: 'moysklad_id = ?',
            whereArgs: [id],
            limit: 1,
          );
          if (old.isEmpty) {
            await t.insert('organizations', values);
          } else {
            await t.update(
              'organizations',
              values,
              where: 'id = ?',
              whereArgs: [old.first['id']],
            );
          }
        }
      });
    } catch (error) {
      await _recordError(
        'Синхронизация организаций',
        'ORGANIZATION_SYNC_FAILED',
        error,
      );
      rethrow;
    }
  }

  Future<List<Map<String, Object?>>> organizations() => _db.then(
    (d) => d.query(
      'organizations',
      where: 'is_present=1 AND is_archived=0',
      orderBy: 'name COLLATE NOCASE',
    ),
  );
  Future<List<Map<String, Object?>>> paymentMethods() => _db.then(
    (d) => d.query('payment_methods', orderBy: 'name COLLATE NOCASE'),
  );
  Future<void> savePaymentMethod(String name, {int? id}) => _guard(
    'Сохранение способа оплаты',
    'PAYMENT_METHOD_SAVE_FAILED',
    () => _savePaymentMethod(name, id: id),
  );

  Future<void> _savePaymentMethod(String name, {int? id}) async {
    final n = name.trim();
    if (n.isEmpty) throw ArgumentError('Укажите название');
    final d = await _db, now = DateTime.now().millisecondsSinceEpoch;
    if (id == null) {
      await d.insert('payment_methods', {
        'name': n,
        'created_at': now,
        'updated_at': now,
      });
    } else {
      await d.update(
        'payment_methods',
        {'name': n, 'updated_at': now},
        where: 'id=?',
        whereArgs: [id],
      );
    }
  }

  Future<void> deletePaymentMethod(int id) => _guard(
    'Удаление способа оплаты',
    'PAYMENT_METHOD_DELETE_FAILED',
    () async {
      await (await _db).delete(
        'payment_methods',
        where: 'id=?',
        whereArgs: [id],
      );
    },
  );
  Future<void> assignPaymentMethod(int orgId, int? methodId) => _guard(
    'Назначение способа оплаты организации',
    'PAYMENT_ASSIGNMENT_FAILED',
    () => _assignPaymentMethod(orgId, methodId),
  );

  Future<void> _assignPaymentMethod(int orgId, int? methodId) async {
    final d = await _db;
    await d.transaction((t) async {
      await t.update(
        'payment_methods',
        {'organization_id': null},
        where: 'organization_id=?',
        whereArgs: [orgId],
      );
      if (methodId != null) {
        await t.update(
          'payment_methods',
          {'organization_id': null},
          where: 'id=?',
          whereArgs: [methodId],
        );
        await t.update(
          'payment_methods',
          {'organization_id': orgId},
          where: 'id=?',
          whereArgs: [methodId],
        );
      }
    });
  }

  Future<List<Map<String, dynamic>>> searchSuppliers(String q) async {
    final s = q.trim();
    if (s.length < 2) return [];
    final r = await api.requestGet(
      uid:
          'supplier-search:${s.toLowerCase()}:${DateTime.now().microsecondsSinceEpoch}',
      type: 'supplier_search',
      logicalQueue: 'suppliers',
      path: '/entity/counterparty',
      query: {'search': s, 'limit': '50'},
    );
    final rows = r['rows'];
    return rows is List
        ? rows
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
        : [];
  }

  Future<void> openSupplierCard(Map<String, dynamic> r) => _guard(
    'Сохранение карточки поставщика',
    'SUPPLIER_SAVE_FAILED',
    () => _openSupplierCard(r),
  );

  Future<void> _openSupplierCard(Map<String, dynamic> r) async {
    final id = r['id']?.toString(), name = r['name']?.toString();
    if (id == null || name == null) {
      throw const FormatException('Карточка поставщика некорректна');
    }
    final d = await _db,
        old = await d.query(
          'suppliers',
          where: 'moysklad_id=?',
          whereArgs: [id],
          limit: 1,
        );
    final values = {
      'moysklad_id': id,
      'name': name,
      'phone': r['phone']?.toString(),
      'relevance_status': old.isEmpty ? 'other' : old.first['relevance_status'],
      'payment_method_id': old.isEmpty ? null : old.first['payment_method_id'],
      'last_synced_at': DateTime.now().millisecondsSinceEpoch,
      'raw_sync_json': jsonEncode(r),
    };
    if (old.isEmpty) {
      await d.insert('suppliers', values);
    } else {
      await d.update(
        'suppliers',
        values,
        where: 'id = ?',
        whereArgs: [old.first['id']],
      );
    }
  }

  Future<List<Map<String, Object?>>> suppliers({
    String search = '',
    String status = 'current',
  }) => _db.then(
    (d) => d.query(
      'suppliers',
      where: 'relevance_status=? AND name LIKE ?',
      whereArgs: [status, '%${search.trim()}%'],
      orderBy: 'name COLLATE NOCASE',
    ),
  );
  Future<void> setSupplierStatus(int id, String status) => _db.then(
    (d) => d.update(
      'suppliers',
      {'relevance_status': status},
      where: 'id=?',
      whereArgs: [id],
    ),
  );
  Future<void> setSupplierPaymentMethod(int id, int? method) => _db.then(
    (d) => d.update(
      'suppliers',
      {'payment_method_id': method},
      where: 'id=?',
      whereArgs: [id],
    ),
  );
  Future<List<Map<String, Object?>>> supplierPaymentDetails(int id) =>
      (_db.then(
        (d) => d.rawQuery(
          '''SELECT s.*,p.name payment_method_name,p.organization_id,o.moysklad_id organization_moysklad_id,o.name organization_name FROM suppliers s LEFT JOIN payment_methods p ON p.id=s.payment_method_id LEFT JOIN organizations o ON o.id=p.organization_id WHERE s.id=?''',
          [id],
        ),
      ));
}
