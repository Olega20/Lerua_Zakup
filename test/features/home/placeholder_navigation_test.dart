import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lerua_zakup/app/app.dart';
import 'package:lerua_zakup/core/storage/preferences_store.dart';
import 'package:lerua_zakup/core/storage/secure_token_store.dart';
import 'package:lerua_zakup/features/settings/data/settings_repository.dart';
import 'package:lerua_zakup/features/warehouse_log/data/warehouse_log_repository.dart';
import 'package:lerua_zakup/features/warehouse_log/data/warehouse_log_storage.dart';
import 'package:lerua_zakup/features/warehouse_log/domain/warehouse_log_entry.dart';

class _Preferences implements PreferencesStore {
  @override
  Future<ThemeMode?> readTheme() async => null;
  @override
  Future<void> writeTheme(ThemeMode mode) async {}
  @override
  Future<int?> readSeedColor() async => null;
  @override
  Future<void> writeSeedColor(int argb) async {}
  @override
  Future<void> clearUserPreferences() async {}
}

class _SecureStore implements SecureTokenStore {
  @override
  Future<String?> readToken() async => null;
  @override
  Future<void> writeToken(String token) async {}
  @override
  Future<void> deleteToken() async {}
}

class _TestWarehouseLogStorage implements WarehouseLogStorage {
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

SettingsRepository _testRepository() => SettingsRepository(
  preferencesStore: _Preferences(),
  secureTokenStore: _SecureStore(),
);

void main() {
  testWidgets('each business button shows the exact development message', (
    tester,
  ) async {
    await tester.pumpWidget(const LeruaZakupApp());

    for (final label in [
      'Закупка',
      'Заказ',
      'Перемещение',
      'Инвентаризация',
      'Прочие действия',
    ]) {
      await tester.tap(find.text(label));
      await tester.pump();
      if (label == 'Прочие действия') {
        await tester.pumpAndSettle();
        expect(find.text('Актуальные товары МойСклад'), findsOneWidget);
      } else {
        expect(
          find.text('Функция находится в разработке'),
          findsOneWidget,
          reason: label,
        );
        await tester.tapAt(const Offset(8, 8));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump();
      }
    }
  });

  testWidgets('Other actions opens the diagnostic warehouse journal', (
    tester,
  ) async {
    await tester.pumpWidget(
      LeruaZakupApp(
        settingsRepository: _testRepository(),
        warehouseLogRepository: WarehouseLogRepository(
          storage: _TestWarehouseLogStorage(),
        ),
        appVersionOverride: '1.0.0+1',
      ),
    );

    await tester.tap(find.text('Прочие действия'));
    await tester.pumpAndSettle();

    expect(find.text('Журнал склада'), findsOneWidget);
    await tester.tap(find.text('Журнал склада'));
    await tester.pumpAndSettle();
    expect(find.text('Журнал пока пуст'), findsOneWidget);
  });

  testWidgets('calendar button opens full calendar and back returns to Home', (
    tester,
  ) async {
    await tester.pumpWidget(const LeruaZakupApp());

    await tester.tap(find.byKey(const ValueKey('expand-calendar')));
    await tester.pumpAndSettle();
    expect(find.textContaining('2026'), findsNothing);
    expect(find.text('Нет операций за этот день'), findsOneWidget);

    await tester.tap(find.byTooltip('Назад'));
    await tester.pumpAndSettle();
    expect(find.text('Закупка'), findsOneWidget);
  });
}
