import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lerua_zakup/app/app_theme.dart';
import 'package:lerua_zakup/core/storage/preferences_store.dart';
import 'package:lerua_zakup/core/storage/secure_token_store.dart';
import 'package:lerua_zakup/features/settings/data/settings_repository.dart';
import 'package:lerua_zakup/features/settings/presentation/settings_screen.dart';

class TestPreferencesStore implements PreferencesStore {
  ThemeMode? theme;
  int? seedColor;
  bool failWrite = false;

  @override
  Future<ThemeMode?> readTheme() async => theme;

  @override
  Future<void> writeTheme(ThemeMode mode) async {
    if (failWrite) throw StateError('preferences failure');
    theme = mode;
  }

  @override
  Future<int?> readSeedColor() async => seedColor;

  @override
  Future<void> writeSeedColor(int argb) async => seedColor = argb;

  @override
  Future<void> clearUserPreferences() async {
    theme = null;
    seedColor = null;
  }
}

class TestSecureStore implements SecureTokenStore {
  String? token;
  bool failWrite = false;

  @override
  Future<String?> readToken() async => token;

  @override
  Future<void> writeToken(String value) async {
    if (failWrite) throw StateError('secure failure');
    token = value;
  }

  @override
  Future<void> deleteToken() async => token = null;
}

void main() {
  late TestPreferencesStore preferences;
  late TestSecureStore secure;
  late SettingsRepository repository;
  var themeChanges = <ThemeMode>[];

  setUp(() {
    preferences = TestPreferencesStore();
    secure = TestSecureStore();
    repository = SettingsRepository(
      preferencesStore: preferences,
      secureTokenStore: secure,
    );
    themeChanges = [];
  });

  Widget app() => MaterialApp(
    home: SettingsScreen(
      repository: repository,
      appVersion: '1.0.0+1',
      onThemeChanged: themeChanges.add,
      onSeedColorChanged: (_) {},
    ),
  );

  testWidgets('shows three separate theme buttons and applies selection', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('Светлая'), findsOneWidget);
    expect(find.text('Тёмная'), findsOneWidget);
    expect(find.text('Системная'), findsOneWidget);

    await tester.tap(find.text('Тёмная'));
    await tester.pumpAndSettle();
    expect(preferences.theme, ThemeMode.dark);
    expect(themeChanges, [ThemeMode.dark]);
  });

  testWidgets('opens the HSV color selector and persists the confirmed color', (
    tester,
  ) async {
    final colorChanges = <Color>[];
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          repository: repository,
          appVersion: '1.0.0+1',
          onThemeChanged: themeChanges.add,
          onSeedColorChanged: colorChanges.add,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('primary-color-setting')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('hue-wheel')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('saturation-value-picker')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('apply-primary-color')));
    await tester.pumpAndSettle();
    expect(preferences.seedColor, AppTheme.defaultSeedColor.toARGB32());
    expect(colorChanges, isNotEmpty);
  });

  testWidgets('token input can be revealed and hidden before saving', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    final fieldFinder = find.byKey(const ValueKey('api-token-field'));
    await tester.enterText(fieldFinder, 'temporary-token');
    expect(tester.widget<TextField>(fieldFinder).obscureText, isTrue);

    await tester.tap(find.byKey(const ValueKey('toggle-api-token-visibility')));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(fieldFinder).obscureText, isFalse);
    expect(find.text('temporary-token'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('toggle-api-token-visibility')));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(fieldFinder).obscureText, isTrue);
  });

  testWidgets('saves token masked and leaves field populated with mask', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('api-token-field')),
      'secret token',
    );
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();

    expect(secure.token, 'secrettoken');
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('api-token-field')),
    );
    expect(field.obscureText, isTrue);
    expect(field.controller!.text, isNot('secrettoken'));
    expect(
      find.byKey(const ValueKey('toggle-api-token-visibility')),
      findsNothing,
    );
  });

  testWidgets('empty token is not saved', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(secure.token, isNull);
    expect(
      find.descendant(
        of: find.byType(SnackBar),
        matching: find.text('Введите API-токен'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('deleting token requires confirmation', (tester) async {
    secure.token = 'existing';
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Удалить токен'));
    await tester.pumpAndSettle();
    expect(secure.token, 'existing');
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(secure.token, 'existing');
  });

  testWidgets('reset asks separately before deleting token', (tester) async {
    secure.token = 'existing';
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сбросить настройки'));
    await tester.pumpAndSettle();
    expect(find.text('Сбросить настройки?'), findsOneWidget);
    await tester.tap(find.text('Сбросить'));
    await tester.pumpAndSettle();
    expect(find.text('Удалить сохранённый API-токен?'), findsOneWidget);
    await tester.tap(find.text('Оставить токен'));
    await tester.pumpAndSettle();
    expect(secure.token, 'existing');
    expect(preferences.theme, isNull);
  });

  testWidgets('shows version in Settings', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('Версия 1.0.0+1'), findsOneWidget);
  });

  testWidgets('confirmed token deletion clears the masked field', (
    tester,
  ) async {
    secure.token = 'existing';
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Удалить токен'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Удалить'));
    await tester.pumpAndSettle();

    expect(secure.token, isNull);
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('api-token-field')),
    );
    expect(field.controller!.text, isEmpty);
    expect(field.readOnly, isFalse);
  });

  testWidgets('reset deletes token only after its second confirmation', (
    tester,
  ) async {
    secure.token = 'existing';
    preferences.theme = ThemeMode.dark;
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Сбросить настройки'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сбросить'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Удалить'));
    await tester.pumpAndSettle();

    expect(secure.token, isNull);
    expect(preferences.theme, isNull);
    expect(themeChanges, [ThemeMode.light]);
  });

  testWidgets(
    'secure storage failure keeps entered token in the masked field',
    (tester) async {
      secure.failWrite = true;
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('api-token-field')),
        'private',
      );
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('api-token-field')),
      );
      expect(field.controller!.text, 'private');
      expect(field.obscureText, isTrue);
      expect(find.text('Не удалось сохранить API-токен'), findsOneWidget);
    },
  );
}
