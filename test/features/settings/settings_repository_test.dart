import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lerua_zakup/core/storage/preferences_store.dart';
import 'package:lerua_zakup/core/storage/secure_token_store.dart';
import 'package:lerua_zakup/features/settings/data/settings_repository.dart';

class MemoryPreferencesStore implements PreferencesStore {
  ThemeMode? theme;
  bool failRead = false;
  bool failWrite = false;
  bool failClear = false;

  @override
  Future<ThemeMode?> readTheme() async {
    if (failRead) throw StateError('preferences read failed');
    return theme;
  }

  @override
  Future<void> writeTheme(ThemeMode mode) async {
    if (failWrite) throw StateError('preferences write failed');
    theme = mode;
  }

  @override
  Future<void> clearUserPreferences() async {
    if (failClear) throw StateError('preferences clear failed');
    theme = null;
  }
}

class MemorySecureTokenStore implements SecureTokenStore {
  String? token;
  bool failRead = false;
  bool failWrite = false;
  bool failDelete = false;

  @override
  Future<String?> readToken() async {
    if (failRead) throw StateError('secure read failed');
    return token;
  }

  @override
  Future<void> writeToken(String value) async {
    if (failWrite) throw StateError('secure write failed');
    token = value;
  }

  @override
  Future<void> deleteToken() async {
    if (failDelete) throw StateError('secure delete failed');
    token = null;
  }
}

void main() {
  late MemoryPreferencesStore preferences;
  late MemorySecureTokenStore secure;
  late SettingsRepository repository;

  setUp(() {
    preferences = MemoryPreferencesStore();
    secure = MemorySecureTokenStore();
    repository = SettingsRepository(
      preferencesStore: preferences,
      secureTokenStore: secure,
    );
  });

  test('falls back to System when theme is absent or unreadable', () async {
    expect(await repository.loadTheme(), ThemeMode.light);
    preferences.failRead = true;
    expect(await repository.loadTheme(), ThemeMode.system);
  });

  test('persists theme selection', () async {
    await repository.saveTheme(ThemeMode.dark);
    expect(preferences.theme, ThemeMode.dark);
  });

  test('removes all whitespace before saving token', () async {
    final result = await repository.saveToken('  ab c\n d\t e  ');
    expect(result, SaveTokenResult.saved);
    expect(secure.token, 'abcde');
  });

  test('empty token is rejected without storage access', () async {
    final result = await repository.saveToken(' \n\t ');
    expect(result, SaveTokenResult.emptyInput);
    expect(secure.token, isNull);
  });

  test('existing token must be deleted before replacement', () async {
    secure.token = 'existing';
    final result = await repository.saveToken('replacement');
    expect(result, SaveTokenResult.tokenAlreadyExists);
    expect(secure.token, 'existing');
  });

  test('does not expose secure storage exceptions as token data', () async {
    secure.failWrite = true;
    final result = await repository.saveToken('private-token');
    expect(result, SaveTokenResult.storageError);
    expect(secure.token, isNull);
  });

  test('failed theme write is propagated for UI feedback', () async {
    preferences.failWrite = true;
    await expectLater(repository.saveTheme(ThemeMode.dark), throwsStateError);
  });

  test('reset preserves token unless its separate confirmation was given', () async {
    preferences.theme = ThemeMode.dark;
    secure.token = 'keep-me';
    await repository.resetSettings(confirmTokenDeletion: false);
    expect(preferences.theme, isNull);
    expect(secure.token, 'keep-me');
  });

  test('reset deletes token only after explicit confirmation', () async {
    preferences.theme = ThemeMode.dark;
    secure.token = 'delete-me';
    await repository.resetSettings(confirmTokenDeletion: true);
    expect(preferences.theme, isNull);
    expect(secure.token, isNull);
  });

  test('reset reports storage failure', () async {
    preferences.failClear = true;
    await expectLater(
      repository.resetSettings(confirmTokenDeletion: false),
      throwsStateError,
    );
  });
}
