import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lerua_zakup/core/storage/app_database.dart';
import 'package:lerua_zakup/core/storage/secure_token_store.dart';
import 'package:lerua_zakup/features/connectivity/data/api_task_dispatcher.dart';
import 'package:lerua_zakup/features/connectivity/data/api_task_repository.dart';
import 'package:lerua_zakup/features/connectivity/data/moysklad_api_client.dart';
import 'package:lerua_zakup/features/references/data/reference_data_repository.dart';
import 'package:lerua_zakup/features/references/presentation/inventory_screens.dart';

class _TokenStore implements SecureTokenStore {
  @override
  Future<String?> readToken() async => 'test-token';

  @override
  Future<void> writeToken(String token) async {}

  @override
  Future<void> deleteToken() async {}
}

class _MemoryInventoryRepository extends ReferenceDataRepository {
  _MemoryInventoryRepository() : this._(AppDatabase());

  _MemoryInventoryRepository._(AppDatabase database)
    : super(
        database: database,
        api: ApiTaskDispatcher(
          repository: ApiTaskRepository(database: database),
          apiClient: MoySkladApiClient(),
          tokenStore: _TokenStore(),
          internet: const Stream<bool>.empty(),
        ),
        directApiClient: MoySkladApiClient(),
        tokenStore: _TokenStore(),
      );

  final List<Map<String, Object?>> lines = [
    {
      'id': 1,
      'product_name_snapshot': 'Товар UI',
      'expected_stock': 7,
      'actual_quantity': null,
      'uom_name_snapshot': 'шт',
      'include_in_inventory': 1,
    },
  ];

  final List<Map<String, Object?>> sessions = [
    {
      'id': 42,
      'status': 'draft',
      'warehouse_name_snapshot': 'Склад UI',
      'organization_name_snapshot': 'Организация UI',
    },
  ];

  @override
  Future<List<Map<String, Object?>>> inventoryLines(int sessionId) async =>
      lines.map(Map<String, Object?>.from).toList();

  @override
  Future<List<Map<String, Object?>>> inventorySessions() async =>
      sessions.map(Map<String, Object?>.from).toList();

  @override
  Future<void> saveInventoryCount(int lineId, double? quantity) async {
    final lineIndex = lines.indexWhere((line) => line['id'] == lineId);
    if (lineIndex < 0) {
      throw StateError('Строка инвентаризации не найдена');
    }
    lines[lineIndex] = {...lines[lineIndex], 'actual_quantity': quantity};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'inventory keypad saves counts and list mode remains switchable',
    (tester) async {
      final repository = _MemoryInventoryRepository();
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1;

      await tester.pumpWidget(
        MaterialApp(
          home: InventorySessionScreen(repository: repository, sessionId: 42),
        ),
      );
      // Do not use pumpAndSettle: the focused read-only quantity field
      // keeps its cursor blink animation alive, so the tree never settles.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Товар UI'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, '1').first);
      await tester.pump();
      await tester.pump();
      expect(
        repository.lines.single['actual_quantity'],
        1,
        reason: 'Keypad count was not passed to the repository',
      );

      await tester.tap(find.byTooltip('Список товаров'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Товар UI'), findsOneWidget);
      expect(find.textContaining('Факт: 1 шт'), findsOneWidget);

      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
