import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lerua_zakup/core/storage/preferences_store.dart';

class FakePreferencesStore implements PreferencesStore {
  ThemeMode? storedTheme;
  bool shouldThrow = false;
  bool cleared = false;

  @override
  Future<ThemeMode?> readTheme() async {
    if (shouldThrow) throw StateError('read failed');
    return storedTheme;
  }

  @override
  Future<void> writeTheme(ThemeMode mode) async {
    if (shouldThrow) throw StateError('write failed');
    storedTheme = mode;
  }

  @override
  Future<void> clearUserPreferences() async {
    if (shouldThrow) throw StateError('clear failed');
    storedTheme = null;
    cleared = true;
  }
}

void main() {
  test('returns null when no theme preference exists', () async {
    final store = FakePreferencesStore();
    expect(await store.readTheme(), isNull);
  });

  test('persists all three theme modes', () async {
    final store = FakePreferencesStore();
    for (final mode in ThemeMode.values) {
      await store.writeTheme(mode);
      expect(await store.readTheme(), mode);
    }
  });

  test('clears user preferences on reset', () async {
    final store = FakePreferencesStore()..storedTheme = ThemeMode.dark;
    await store.clearUserPreferences();
    expect(store.cleared, isTrue);
    expect(await store.readTheme(), isNull);
  });

  test('propagates storage errors to its caller', () async {
    final store = FakePreferencesStore()..shouldThrow = true;
    await expectLater(store.readTheme(), throwsStateError);
    await expectLater(store.writeTheme(ThemeMode.dark), throwsStateError);
    await expectLater(store.clearUserPreferences(), throwsStateError);
  });
}
