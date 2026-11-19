import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lerua_zakup/features/warehouse_log/data/warehouse_log_repository.dart';
import 'package:lerua_zakup/features/warehouse_log/data/warehouse_log_storage.dart';
import 'package:lerua_zakup/features/warehouse_log/domain/warehouse_log_entry.dart';
import 'package:lerua_zakup/features/warehouse_log/presentation/warehouse_log_screen.dart';

class _MemoryWarehouseLogStorage implements WarehouseLogStorage {
  final entries = <WarehouseLogEntry>[];

  @override
  Future<void> insert(WarehouseLogEntry entry, {required int limit}) async {
    entries.insert(0, entry);
    if (entries.length > limit) entries.removeRange(limit, entries.length);
  }

  @override
  Future<List<WarehouseLogEntry>> latest({required int limit}) async =>
      entries.take(limit).toList();

  @override
  Future<void> clear() async => entries.clear();
}

void main() {
  late _MemoryWarehouseLogStorage storage;
  late WarehouseLogRepository repository;

  setUp(() {
    storage = _MemoryWarehouseLogStorage();
    repository = WarehouseLogRepository(storage: storage);
  });

  Widget app() => MaterialApp(home: WarehouseLogScreen(repository: repository));

  testWidgets('shows an empty state when no diagnostics exist', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('Журнал склада'), findsOneWidget);
    expect(find.text('Журнал пока пуст'), findsOneWidget);
  });

  testWidgets('shows diagnostic entries and opens safe details', (
    tester,
  ) async {
    await repository.record(
      level: WarehouseLogLevel.error,
      type: WarehouseLogEventType.unauthorized,
      description: 'API отклонил Access Token',
      httpStatusCode: 401,
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('Ошибка авторизации'), findsOneWidget);
    await tester.tap(find.text('Ошибка авторизации'));
    await tester.pumpAndSettle();

    expect(find.text('HTTP: 401', skipOffstage: false), findsOneWidget);
    expect(find.text('Копировать'), findsOneWidget);
    expect(find.text('Закрыть'), findsOneWidget);
  });

  testWidgets('clears entries only after confirmation', (tester) async {
    await repository.record(
      level: WarehouseLogLevel.info,
      type: WarehouseLogEventType.checkSucceeded,
      description: 'МойСклад ответил успешно',
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Очистить журнал'));
    await tester.pumpAndSettle();

    expect(find.text('Очистить журнал?'), findsOneWidget);
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(find.text('Подключение подтверждено'), findsOneWidget);

    await tester.tap(find.byTooltip('Очистить журнал'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Очистить'));
    await tester.pumpAndSettle();
    expect(find.text('Журнал пока пуст'), findsOneWidget);
  });
}
