import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lerua_zakup/app/app.dart';
import 'package:lerua_zakup/core/storage/preferences_store.dart';
import 'package:lerua_zakup/core/storage/secure_token_store.dart';
import 'package:lerua_zakup/features/settings/data/settings_repository.dart';

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
      expect(
        find.text('Функция находится в разработке'),
        findsOneWidget,
        reason: label,
      );
      await tester.tapAt(const Offset(8, 8));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
    }
  });

  testWidgets(
    'Settings opens a non-empty placeholder with Warehouse Journal action',
    (tester) async {
      await tester.pumpWidget(
        LeruaZakupApp(
          settingsRepository: _testRepository(),
          appVersionOverride: '1.0.0+1',
        ),
      );

      await tester.tap(find.text('Настройки'));
      await tester.pumpAndSettle();

      expect(find.text('Настройки'), findsOneWidget);
      expect(find.text('Журнал склада'), findsOneWidget);
      await tester.tap(find.text('Журнал склада'));
      await tester.pump();
      expect(find.text('Функция находится в разработке'), findsOneWidget);
    },
  );

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
