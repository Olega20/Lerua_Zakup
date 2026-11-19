import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lerua_zakup/app/app.dart';
import 'package:lerua_zakup/core/storage/preferences_store.dart';
import 'package:lerua_zakup/core/storage/secure_token_store.dart';
import 'package:lerua_zakup/features/settings/data/settings_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemorySecureTokenStore implements SecureTokenStore {
  String? token;

  @override
  Future<String?> readToken() async => token;

  @override
  Future<void> writeToken(String value) async => token = value;

  @override
  Future<void> deleteToken() async => token = null;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('offline startup shell smoke test', (tester) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.clear();
    await preferences.setBool('notification_permission_requested', true);
    final repository = SettingsRepository(
      preferencesStore: SharedPreferencesStore(),
      secureTokenStore: _MemorySecureTokenStore(),
    );

    await tester.pumpWidget(
      LeruaZakupApp(
        settingsRepository: repository,
        appVersionOverride: '1.0.0+1',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Закупка'), findsOneWidget);
    expect(find.text('Настройки'), findsOneWidget);
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
    expect(await preferences.getString('theme_mode'), ThemeMode.dark.name);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Заказ'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('expand-calendar')));
    await tester.pumpAndSettle();
    expect(find.text('Нет операций за этот день'), findsOneWidget);
    expect(find.byKey(const ValueKey('calendar-month-grid')), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Закупка'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      LeruaZakupApp(
        settingsRepository: repository,
        appVersionOverride: '1.0.0+1',
      ),
    );
    await tester.pumpAndSettle();

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
    expect(find.text('Закупка'), findsOneWidget);
  });
}
