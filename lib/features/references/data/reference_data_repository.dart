import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../../core/storage/app_database.dart';
import '../../../core/storage/secure_token_store.dart';
import '../../connectivity/data/moysklad_api_client.dart';
import '../../connectivity/domain/api_task.dart';
import '../../../core/diagnostics/emergency_diagnostic_sink.dart';
import '../../connectivity/data/api_task_dispatcher.dart';
import '../../connectivity/domain/api_task_execution_exception.dart';
import '../../warehouse_log/data/warehouse_log_repository.dart';
import '../../warehouse_log/domain/warehouse_log_entry.dart';

class ReferenceDataRepository {
  ReferenceDataRepository({
    required this.database,
    required this.api,
    required this.directApiClient,
    required this.tokenStore,
    this.warehouseLog,
  });
  final AppDatabase database;
  final ApiTaskDispatcher api;
  final MoySkladApiClient directApiClient;
  final SecureTokenStore tokenStore;
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
    final errorCode = code;
    final details = <String>[
      'Тип исключения: ${error.runtimeType}',
      if (apiError == null)
        'Подробности: ${sanitizeDiagnosticText(error.toString())}',
      if (apiError?.taskId != null) 'Задача: ${apiError!.taskId}',
      if (apiError?.attemptNumber != null)
        'Попытка: ${apiError!.attemptNumber}',
      if (apiError?.httpStatusCode != null) 'HTTP: ${apiError!.httpStatusCode}',
      if (apiError?.safeErrorCode != null)
        'Код API: ${apiError!.safeErrorCode}',
      if (apiError?.safeErrorMessage != null)
        'Сообщение API: ${apiError!.safeErrorMessage}',
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
          ? 'Проверьте права Access Token на чтение справочника «$component» в МойСклад.'
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

  /// Temporary diagnostic path: fetches pages directly through the HTTP client,
  /// without enqueueing or waiting for the API task dispatcher.
  Future<List<Map<String, dynamic>>> _allDirect(
    String path, {
    String? filter,
  }) async {
    final token = await tokenStore.readToken();
    if (token == null || token.trim().isEmpty) {
      throw StateError('Не сохранён Access Token');
    }
    const limit = 100;
    var offset = 0;
    final result = <Map<String, dynamic>>[];
    while (true) {
      final query = <String, String>{'limit': '$limit', 'offset': '$offset'};
      if (filter != null) query['filter'] = filter;
      final response = await directApiClient.getResource(
        token,
        path,
        query: query,
      );
      if (!response.isSuccess) {
        throw ApiTaskExecutionException(
          ApiTaskStatus.failed,
          response.errorResponse ?? response.data,
          httpStatusCode: response.statusCode,
          safeErrorCode: response.errorCode,
          safeErrorMessage: response.errorMessage,
        );
      }
      final data = response.data!;
      final rows = data['rows'];
      if (rows is! List) {
        throw const FormatException('В ответе МойСклад отсутствует rows');
      }
      result.addAll(
        rows.whereType<Map>().map((row) => Map<String, dynamic>.from(row)),
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
      List<Map<String, dynamic>>? stockByStoreRows;
      try {
        stockByStoreRows = await _all(
          '/report/stock/bystore',
          'product_stock_by_store',
          'catalog',
        );
      } catch (_) {
        // Keep the last successful per-warehouse snapshot if this optional
        // report is temporarily unavailable; total stock sync can still finish.
      }
      final uomNames = <String, String>{};
      for (final row in rows) {
        final uom = row['uom'];
        if (uom is! Map) continue;
        final directName = uom['name']?.toString().trim();
        if (directName != null && directName.isNotEmpty) continue;
        final meta = uom['meta'];
        final href = meta is Map ? meta['href']?.toString() : null;
        if (href == null) continue;
        final segments = Uri.tryParse(href)?.pathSegments
            .where((segment) => segment.isNotEmpty)
            .toList();
        if (segments == null || segments.isEmpty) continue;
        final uomId = segments.last;
        if (uomNames.containsKey(uomId)) continue;
        try {
          final details = await api.requestGet(
            uid: 'catalog-uom:$uomId:${DateTime.now().microsecondsSinceEpoch}',
            type: 'reference_item',
            logicalQueue: 'catalog',
            path: '/entity/uom/$uomId',
          );
          final name = details['name']?.toString().trim();
          if (name != null && name.isNotEmpty) uomNames[uomId] = name;
        } catch (_) {
          // Missing unit metadata must not abort an otherwise valid catalog sync.
        }
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
              ? (uom['name']?.toString().trim().isNotEmpty == true
                    ? uom['name'].toString().trim()
                    : _uomNameFromHref(uom, uomNames))
              : '\u041d\u0435 \u0443\u043a\u0430\u0437\u0430\u043d\u043e',
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
        final storeStockSnapshot = stockByStoreRows;
        if (storeStockSnapshot != null) {
          await t.delete('product_warehouse_stock');
          final localProducts = await t.query(
            'products',
            columns: ['id', 'moysklad_id'],
            where: 'is_present=1',
          );
          final localProductIds = {
            for (final product in localProducts)
              product['moysklad_id'] as String: product['id'] as int,
          };
          final stockUpdatedAt = DateTime.now().millisecondsSinceEpoch;
          for (final stockRow in storeStockSnapshot) {
            final productMeta = stockRow['meta'];
            final productHref = productMeta is Map
                ? productMeta['href']?.toString()
                : null;
            final productMoyskladId = productHref == null
                ? null
                : Uri.tryParse(productHref)?.pathSegments
                      .where((segment) => segment.isNotEmpty)
                      .lastOrNull;
            final productId = productMoyskladId == null
                ? null
                : localProductIds[productMoyskladId];
            final storeRows = stockRow['stockByStore'];
            if (productId == null || storeRows is! List) continue;
            for (final storeRow in storeRows.whereType<Map>()) {
              final storeMeta = storeRow['meta'];
              final storeHref = storeMeta is Map
                  ? storeMeta['href']?.toString()
                  : null;
              final storeId = storeHref == null
                  ? null
                  : Uri.tryParse(storeHref)?.pathSegments
                        .where((segment) => segment.isNotEmpty)
                        .lastOrNull;
              final storeName = storeRow['name']?.toString();
              final quantity = (storeRow['stock'] as num?)?.toDouble();
              if (storeId == null || storeName == null || quantity == null) {
                continue;
              }
              await t.insert('product_warehouse_stock', {
                'product_id': productId,
                'warehouse_moysklad_id': storeId,
                'warehouse_name': storeName,
                'stock': quantity,
                'updated_at': stockUpdatedAt,
              }, conflictAlgorithm: ConflictAlgorithm.replace);
            }
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

  String _uomNameFromHref(Map uom, Map<String, String> names) {
    final meta = uom['meta'];
    final href = meta is Map ? meta['href']?.toString() : null;
    if (href == null) {
      return '\u041d\u0435 \u0443\u043a\u0430\u0437\u0430\u043d\u043e';
    }
    final segments = Uri.tryParse(href)?.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList();
    if (segments == null || segments.isEmpty) {
      return '\u041d\u0435 \u0443\u043a\u0430\u0437\u0430\u043d\u043e';
    }
    return names[segments.last] ??
        '\u041d\u0435 \u0443\u043a\u0430\u0437\u0430\u043d\u043e';
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
    String? warehouseMoyskladId,
  }) async {
    final clauses = <String>['p.is_archived=?', 'p.is_present=1'];
    final args = <Object?>[archived ? 1 : 0];
    if (status != null) {
      clauses.add('p.relevance_status=?');
      args.add(status);
    }
    if (search.trim().isNotEmpty) {
      clauses.add('p.name LIKE ?');
      args.add('%${search.trim()}%');
    }
    if (warehouseMoyskladId != null) {
      clauses.add(
        '(EXISTS (SELECT 1 FROM product_warehouse_stock ws WHERE ws.product_id=p.id AND ws.warehouse_moysklad_id=?) OR EXISTS (SELECT 1 FROM product_storage_assignments psa2 JOIN warehouses w2 ON w2.id=psa2.warehouse_id WHERE psa2.product_id=p.id AND w2.moysklad_id=?))',
      );
      args
        ..add(warehouseMoyskladId)
        ..add(warehouseMoyskladId);
    }
    return (await _db).rawQuery(
      '''SELECT p.*,s.name AS supplier_name,s.phone AS supplier_phone FROM products p LEFT JOIN product_supplier_assignments psa ON psa.product_id=p.id LEFT JOIN suppliers s ON s.id=psa.supplier_id WHERE ${clauses.join(' AND ')} ORDER BY CASE p.relevance_status WHEN 'unassigned' THEN 0 WHEN 'relevant' THEN 1 ELSE 2 END,p.name COLLATE NOCASE''',
      args,
    );
  }

  Future<List<Map<String, Object?>>> inventorySessions() async {
    return (await _db).query(
      'inventory_sessions',
      orderBy: 'CASE status WHEN \'draft\' THEN 0 WHEN \'sync_failed\' THEN 1 WHEN \'syncing\' THEN 2 ELSE 3 END, updated_at DESC',
    );
  }

  Future<List<Map<String, Object?>>> inventoryLines(int sessionId) async {
    return (await _db).query(
      'inventory_lines',
      where: 'session_id=?',
      whereArgs: [sessionId],
      orderBy: 'sort_order',
    );
  }

  Future<int> createInventoryDraft({
    required int organizationId,
    required int warehouseId,
    required Iterable<int> storageLocationIds,
  }) async {
    final db = await _db;
    final selectedIds = storageLocationIds.toSet().toList()..sort();
    final organizationRows = await db.query(
      'organizations',
      where: 'id=? AND is_present=1 AND is_archived=0',
      whereArgs: [organizationId],
      limit: 1,
    );
    final warehouseRows = await db.query(
      'warehouses',
      where: 'id=? AND is_present=1 AND is_archived=0',
      whereArgs: [warehouseId],
      limit: 1,
    );
    if (organizationRows.isEmpty || warehouseRows.isEmpty) {
      throw StateError(
        'Организация или склад больше недоступны. Обновите справочники.',
      );
    }
    final organization = organizationRows.first;
    final warehouse = warehouseRows.first;
    final locations = await db.query(
      'storage_locations',
      where: 'warehouse_id=? AND is_active=1',
      whereArgs: [warehouseId],
    );
    final validIds = locations.map((row) => row['id'] as int).toSet();
    if (selectedIds.any((id) => !validIds.contains(id))) {
      throw StateError('Список мест хранения изменился. Обновите экран.');
    }
    if (locations.isEmpty) {
      throw StateError('На выбранном складе нет активных мест хранения.');
    }
    final locationFilter = selectedIds.isEmpty
        ? ''
        : ' AND psa.storage_location_id IN (${List.filled(selectedIds.length, '?').join(',')})';
    final products = await db.rawQuery(
      '''
      SELECT p.id AS product_id,p.moysklad_id,p.kind,p.name,p.uom_name,
             pws.stock AS expected_stock,psa.storage_location_id,sl.name AS location_name
      FROM product_storage_assignments psa
      JOIN products p ON p.id=psa.product_id
      JOIN storage_locations sl ON sl.id=psa.storage_location_id
      LEFT JOIN product_warehouse_stock pws
        ON pws.product_id=p.id AND pws.warehouse_moysklad_id=?
      WHERE psa.warehouse_id=? AND sl.is_active=1
        AND p.is_archived=0 AND p.is_present=1
        $locationFilter
      ORDER BY sl.sort_order,sl.name COLLATE NOCASE,p.name COLLATE NOCASE
      ''',
      [warehouse['moysklad_id'], warehouseId, ...selectedIds],
    );
    if (products.isEmpty) {
      throw StateError('В выбранных местах хранения нет назначенных товаров.');
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final uid =
        'inventory-${DateTime.now().microsecondsSinceEpoch}-${organization['moysklad_id']}-${warehouse['moysklad_id']}';
    return db.transaction((txn) async {
      final sessionId = await txn.insert('inventory_sessions', {
        'session_uid': uid,
        'organization_id': organizationId,
        'organization_moysklad_id_snapshot': organization['moysklad_id'],
        'organization_name_snapshot': organization['name'],
        'warehouse_id': warehouseId,
        'warehouse_moysklad_id_snapshot': warehouse['moysklad_id'],
        'warehouse_name_snapshot': warehouse['name'],
        'selected_location_ids_json': jsonEncode(selectedIds),
        'status': 'draft',
        'created_at': now,
        'updated_at': now,
      });
      for (var i = 0; i < products.length; i++) {
        final product = products[i];
        await txn.insert('inventory_lines', {
          'session_id': sessionId,
          'product_id': product['product_id'],
          'product_moysklad_id_snapshot': product['moysklad_id'],
          'product_kind_snapshot': product['kind'],
          'product_name_snapshot': product['name'],
          'uom_name_snapshot': product['uom_name'],
          'expected_stock': product['expected_stock'],
          'actual_quantity': null,
          'include_in_inventory': 1,
          'sort_order': i,
        });
      }
      return sessionId;
    });
  }

  Future<void> saveInventoryCount(int lineId, double? quantity) async {
    if (quantity != null && (!quantity.isFinite || quantity < 0)) {
      throw ArgumentError.value(
        quantity,
        'quantity',
        'Количество должно быть неотрицательным',
      );
    }
    final db = await _db;
    final line = await db.query(
      'inventory_lines',
      columns: ['session_id'],
      where: 'id=?',
      whereArgs: [lineId],
      limit: 1,
    );
    if (line.isEmpty) throw StateError('Строка инвентаризации не найдена');
    await db.update(
      'inventory_lines',
      {
        'actual_quantity': quantity,
        'counted_at': quantity == null
            ? null
            : DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id=?',
      whereArgs: [lineId],
    );
    await db.update(
      'inventory_sessions',
      {'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id=?',
      whereArgs: [line.first['session_id']],
    );
  }

  Future<void> resolveSkippedInventoryLines(
    int sessionId, {
    required Set<int> zeroLineIds,
  }) async {
    final db = await _db;
    await db.transaction((txn) async {
      final skipped = await txn.query(
        'inventory_lines',
        columns: ['id'],
        where: 'session_id=? AND actual_quantity IS NULL',
        whereArgs: [sessionId],
      );
      final skippedIds = skipped.map((row) => row['id'] as int).toSet();
      if (zeroLineIds.difference(skippedIds).isNotEmpty) {
        throw StateError(
          'Список пропущенных товаров изменился. Повторите действие.',
        );
      }
      for (final id in skippedIds) {
        final zero = zeroLineIds.contains(id);
        await txn.update(
          'inventory_lines',
          {
            'actual_quantity': zero ? 0 : null,
            'include_in_inventory': zero ? 1 : 0,
            'counted_at': zero ? DateTime.now().millisecondsSinceEpoch : null,
          },
          where: 'id=? AND session_id=?',
          whereArgs: [id, sessionId],
        );
      }
      await txn.update(
        'inventory_sessions',
        {'updated_at': DateTime.now().millisecondsSinceEpoch},
        where: 'id=?',
        whereArgs: [sessionId],
      );
    });
  }

  Future<void> syncInventorySession(int sessionId) async {
    final db = await _db;
    final sessions = await db.query(
      'inventory_sessions',
      where: 'id=?',
      whereArgs: [sessionId],
      limit: 1,
    );
    if (sessions.isEmpty) throw StateError('Инвентаризация не найдена');
    final session = sessions.first;
    if (session['status'] == 'completed') return;
    final lines = await db.query(
      'inventory_lines',
      where: 'session_id=? AND include_in_inventory=1',
      whereArgs: [sessionId],
      orderBy: 'sort_order',
    );
    if (lines.isEmpty) {
      throw StateError(
        'Нет товаров, которые можно включить в документ инвентаризации.',
      );
    }
    if (lines.any((line) => line['actual_quantity'] == null)) {
      throw StateError('Сначала разрешите обработку пропущенных товаров.');
    }
    if (lines.length > 1000) {
      throw StateError(
        'В одном документе МойСклад поддерживается не более 1000 позиций. Разделите инвентаризацию на несколько документов.',
      );
    }
    await db.update(
      'inventory_sessions',
      {
        'status': 'syncing',
        'sync_error': null,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id=?',
      whereArgs: [sessionId],
    );
    try {
      final uid = session['session_uid'] as String;
      // A previous POST may have reached MoySklad even if its response was lost.
      // externalCode makes retry idempotent: look up the document before creating it again.
      final existing = await api.requestGet(
        uid: 'inventory-lookup:$uid:${DateTime.now().microsecondsSinceEpoch}',
        type: 'inventory_lookup',
        logicalQueue: 'inventory',
        path: '/entity/inventory',
        query: {'filter': 'externalCode=$uid', 'limit': '2'},
        timeout: const Duration(seconds: 45),
      );
      Map<String, dynamic>? document;
      final existingRows = existing['rows'];
      if (existingRows is List && existingRows.isNotEmpty) {
        final row = existingRows.first;
        if (row is Map) document = Map<String, dynamic>.from(row);
      }
      if (document == null) {
        final positions = lines.map((line) {
          final kind = line['product_kind_snapshot'] == 'service'
              ? 'service'
              : 'product';
          final productId = line['product_moysklad_id_snapshot'];
          return {
            'quantity': (line['actual_quantity'] as num).toDouble(),
            'assortment': {
              'meta': {
                'href':
                    'https://api.moysklad.ru/api/remap/1.2/entity/$kind/$productId',
                'type': kind,
                'mediaType': 'application/json',
              },
            },
          };
        }).toList();
        final baseTaskUid = 'inventory-create:$uid';
        final relatedTasks = (await api.listTasks(logicalQueue: 'inventory'))
            .where((task) => task.uid.startsWith(baseTaskUid))
            .toList();
        final previousTask = relatedTasks.isEmpty ? null : relatedTasks.last;
        final previousIsTerminalFailure = previousTask != null &&
            {
              ApiTaskStatus.failed,
              ApiTaskStatus.uncertain,
              ApiTaskStatus.cancelled,
            }.contains(previousTask.status);
        final postTaskUid = previousTask == null
            ? baseTaskUid
            : previousIsTerminalFailure
            ? '$baseTaskUid:retry:${DateTime.now().microsecondsSinceEpoch}'
            : previousTask.uid;
        final created = await api.requestPost(
          uid: postTaskUid,
          type: 'inventory_create',
          logicalQueue: 'inventory',
          path: '/entity/inventory',
          timeout: const Duration(minutes: 3),
          body: {
            'name':
                'Инвентаризация ${DateTime.now().toIso8601String().substring(0, 16)}',
            'externalCode': uid,
            'organization': {
              'meta': {
                'href':
                    'https://api.moysklad.ru/api/remap/1.2/entity/organization/${session['organization_moysklad_id_snapshot']}',
                'type': 'organization',
                'mediaType': 'application/json',
              },
            },
            'store': {
              'meta': {
                'href':
                    'https://api.moysklad.ru/api/remap/1.2/entity/store/${session['warehouse_moysklad_id_snapshot']}',
                'type': 'store',
                'mediaType': 'application/json',
              },
            },
            'positions': positions,
          },
        );
        document = Map<String, dynamic>.from(created);
      }
      final meta = document['meta'];
      final href = meta is Map ? meta['href']?.toString() : null;
      final documentId =
          document['id']?.toString() ??
          (href == null ? null : Uri.tryParse(href)?.pathSegments.lastOrNull);
      if (documentId == null || documentId.isEmpty) {
        throw const FormatException(
          'МойСклад не вернул идентификатор инвентаризации.',
        );
      }
      await db.update(
        'inventory_sessions',
        {
          'status': 'completed',
          'moysklad_id': documentId,
          'moysklad_href': href,
          'sync_error': null,
          'completed_at': DateTime.now().millisecondsSinceEpoch,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id=?',
        whereArgs: [sessionId],
      );
    } catch (error) {
      await db.update(
        'inventory_sessions',
        {
          'status': 'sync_failed',
          'sync_error': error.toString(),
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id=?',
        whereArgs: [sessionId],
      );
      rethrow;
    }
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
      final rows = await _allDirect('/entity/store', filter: 'archived=false');
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
      final orderRows = await db.rawQuery(
        'SELECT COALESCE(MAX(sort_order), -1) + 1 AS next_order FROM storage_locations WHERE warehouse_id=?',
        [warehouseId],
      );
      final nextOrder = orderRows.first['next_order'] as int;
      await db.insert('storage_locations', {
        'warehouse_id': warehouseId,
        'name': n,
        'sort_order': nextOrder,
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

  Future<List<Map<String, Object?>>> productStorageAssignments(int productId) =>
      _db.then(
        (d) => d.rawQuery(
          '''SELECT a.id,a.product_id,a.warehouse_id,a.storage_location_id,a.assigned_at,w.name warehouse_name,w.moysklad_id warehouse_moysklad_id,l.name location_name FROM product_storage_assignments a JOIN warehouses w ON w.id=a.warehouse_id JOIN storage_locations l ON l.id=a.storage_location_id WHERE a.product_id=? AND l.is_active=1 ORDER BY w.name COLLATE NOCASE''',
          [productId],
        ),
      );

  Future<List<Map<String, Object?>>> productWarehouseStocks(int productId) =>
      _db.then(
        (db) => db.query(
          'product_warehouse_stock',
          where: 'product_id=?',
          whereArgs: [productId],
          orderBy: 'warehouse_name COLLATE NOCASE',
        ),
      );

  /// Returns one row per warehouse with either a stock snapshot or a local
  /// storage assignment. Stock is warehouse-level; storage locations are local.
  /// Returns one row per warehouse with either a stock snapshot or a local
  /// storage assignment. Stock is warehouse-level; storage locations are local.
  /// Shows stock only for the warehouse explicitly assigned to the product
  /// through a local storage location. Other warehouse balances are omitted.
  Future<List<Map<String, Object?>>> productWarehouseOverview(
    Iterable<int> productIds,
  ) async {
    final ids = productIds.toSet().toList();
    if (ids.isEmpty) return const [];
    final db = await _db;
    final result = <Map<String, Object?>>[];
    for (var offset = 0; offset < ids.length; offset += 800) {
      final batch = ids.skip(offset).take(800).toList();
      final placeholders = List.filled(batch.length, '?').join(',');
      result.addAll(
        await db.rawQuery('''
          SELECT psa.product_id,
                 w.moysklad_id AS warehouse_moysklad_id,
                 w.name AS warehouse_name,
                 pws.stock,
                 sl.name AS location_name
          FROM product_storage_assignments psa
          JOIN warehouses w ON w.id=psa.warehouse_id
          JOIN storage_locations sl
            ON sl.id=psa.storage_location_id AND sl.is_active=1
          LEFT JOIN product_warehouse_stock pws
            ON pws.product_id=psa.product_id
           AND pws.warehouse_moysklad_id=w.moysklad_id
          WHERE psa.product_id IN ($placeholders)
          ORDER BY psa.product_id,w.name COLLATE NOCASE
          ''', batch),
      );
    }
    return result;
  }

  Future<Map<String, Object?>?> productSupplier(int productId) async {
    final rows = await (await _db).rawQuery(
      '''SELECT s.*,psa.assigned_at FROM product_supplier_assignments psa JOIN suppliers s ON s.id=psa.supplier_id WHERE psa.product_id=? LIMIT 1''',
      [productId],
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> assignSupplierToProducts(
    Iterable<int> productIds,
    Map<String, dynamic> supplier,
  ) => _guard(
    'Назначение поставщика товарам',
    'PRODUCT_SUPPLIER_ASSIGNMENT_FAILED',
    () async {
      final moyskladId = supplier['id']?.toString();
      final name = supplier['name']?.toString();
      if (moyskladId == null ||
          moyskladId.isEmpty ||
          name == null ||
          name.isEmpty) {
        throw const FormatException('Карточка поставщика некорректна');
      }
      final db = await _db;
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.transaction((txn) async {
        final old = await txn.query(
          'suppliers',
          where: 'moysklad_id=?',
          whereArgs: [moyskladId],
          limit: 1,
        );
        final values = <String, Object?>{
          'moysklad_id': moyskladId,
          'name': name,
          'phone': supplier['phone']?.toString(),
          'relevance_status': 'current',
          'payment_method_id': old.isEmpty
              ? null
              : old.first['payment_method_id'],
          'last_synced_at': now,
          'raw_sync_json': jsonEncode(supplier),
        };
        late int supplierId;
        if (old.isEmpty) {
          supplierId = await txn.insert('suppliers', values);
        } else {
          supplierId = old.first['id'] as int;
          await txn.update(
            'suppliers',
            values,
            where: 'id=?',
            whereArgs: [supplierId],
          );
        }
        for (final productId in productIds.toSet()) {
          await txn.insert('product_supplier_assignments', {
            'product_id': productId,
            'supplier_id': supplierId,
            'assigned_at': now,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      });
    },
  );

  Future<void> assignProductsToStorageLocation(
    Iterable<int> productIds,
    int warehouseId,
    int storageLocationId,
  ) => _guard(
    'Назначение мест хранения товарам',
    'PRODUCT_STORAGE_ASSIGNMENT_FAILED',
    () async {
      final db = await _db;
      final location = await db.query(
        'storage_locations',
        columns: ['id'],
        where: 'id=? AND warehouse_id=? AND is_active=1',
        whereArgs: [storageLocationId, warehouseId],
        limit: 1,
      );
      if (location.isEmpty) {
        throw StateError('Место хранения не относится к выбранному складу');
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.transaction((t) async {
        for (final productId in productIds.toSet()) {
          await t.insert('product_storage_assignments', {
            'product_id': productId,
            'warehouse_id': warehouseId,
            'storage_location_id': storageLocationId,
            'assigned_at': now,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      });
    },
  );

  Future<void> removeProductStorageAssignment(int assignmentId) => _db.then(
    (d) => d.delete(
      'product_storage_assignments',
      where: 'id=?',
      whereArgs: [assignmentId],
    ),
  );

  Future<void> reorderStorageLocations(int warehouseId, List<int> orderedIds) =>
      _guard(
        'Изменение порядка мест хранения',
        'STORAGE_LOCATION_REORDER_FAILED',
        () async {
          final db = await _db;
          await db.transaction((t) async {
            final existing = await t.query(
              'storage_locations',
              columns: ['id'],
              where: 'warehouse_id=? AND is_active=1',
              whereArgs: [warehouseId],
            );
            final expected = existing.map((r) => r['id'] as int).toSet();
            if (orderedIds.toSet().length != orderedIds.length ||
                orderedIds.toSet().difference(expected).isNotEmpty ||
                expected.difference(orderedIds.toSet()).isNotEmpty) {
              throw StateError(
                'Список мест хранения изменился; обновите экран',
              );
            }
            for (var i = 0; i < orderedIds.length; i++) {
              await t.update(
                'storage_locations',
                {
                  'sort_order': i,
                  'updated_at': DateTime.now().millisecondsSinceEpoch,
                },
                where: 'id=? AND warehouse_id=?',
                whereArgs: [orderedIds[i], warehouseId],
              );
            }
          });
        },
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
