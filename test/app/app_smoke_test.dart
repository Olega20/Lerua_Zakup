import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lerua_zakup/app/app.dart';
import 'package:lerua_zakup/core/storage/preferences_store.dart';
import 'package:lerua_zakup/core/storage/secure_token_store.dart';
import 'package:lerua_zakup/features/settings/data/settings_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SmokePreferencesStore implements PreferencesStore {
  ThemeMode? theme;

  @override
  Future<ThemeMode?> readTheme() async => theme;

  @override
  Future<void> writeTheme(ThemeMode mode) async => theme = mode;

  @override
  Future<void> clearUserPreferences() async => theme = null;
}

class _SmokeSecureTokenStore implements SecureTokenStore {
  String? token;

  @override
  Future<String?> readToken() async => token;

  @override
  Future<void> writeToken(String value) async => token = value;

  @override
  Future<void> deleteToken() async => token = null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('offline app smoke flow and theme persistence', (tester) async {
    SharedPreferences.setMockInitialValues({
      'notification_permission_requested': true,
    });
    final preferences = _SmokePreferencesStore();
    final repository = SettingsRepository(
      preferencesStore: preferences,
      secureTokenStore: _SmokeSecureTokenStore(),
    );

    await tester.pumpWidget(
      LeruaZakupApp(
        settingsRepository: repository,
        appVersionOverride: '1.0.0+1',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Закупка'), findsOneWidget);
    expect(find.text('Заказ'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('connectivity-indicator')),
      findsOneWidget,
    );

    await tester.tap(find.text('Закупка'));
    await tester.pump();
    expect(find.text('Функция находится в разработке'), findsOneWidget);

    await tester.tap(find.text('Настройки'));
    await tester.pumpAndSettle();
    expect(find.text('Тема оформления'), findsOneWidget);
    await tester.tap(find.text('Тёмная'));
    await tester.pumpAndSettle();
    expect(preferences.theme, ThemeMode.dark);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Закупка'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('expand-calendar')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('calendar-month-grid')), findsOneWidget);
    expect(find.text('Нет операций за этот день'), findsOneWidget);
    await tester.tap(find.text('15').first);
    await tester.pumpAndSettle();
    expect(find.text('Нет операций за этот день'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Настройки'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      LeruaZakupApp(
        settingsRepository: repository,
        appVersionOverride: '1.0.0+1',
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );
    expect(find.text('Закупка'), findsOneWidget);
  });
}
