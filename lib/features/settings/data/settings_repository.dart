import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../core/storage/preferences_store.dart';
import '../../../core/storage/secure_token_store.dart';

enum SaveTokenResult { saved, emptyInput, tokenAlreadyExists, storageError }

class SettingsRepository {
  SettingsRepository({
    required this._preferencesStore,
    required this._secureTokenStore,
  });

  final PreferencesStore _preferencesStore;
  final SecureTokenStore _secureTokenStore;

  Future<ThemeMode> loadTheme() async {
    try {
      return await _preferencesStore.readTheme() ?? ThemeMode.light;
    } catch (_) {
      return ThemeMode.system;
    }
  }

  Future<void> saveTheme(ThemeMode mode) => _preferencesStore.writeTheme(mode);

  Future<Color> loadSeedColor() async {
    try {
      final argb = await _preferencesStore.readSeedColor();
      return argb == null ? AppTheme.defaultSeedColor : Color(argb);
    } catch (_) {
      return AppTheme.defaultSeedColor;
    }
  }

  Future<void> saveSeedColor(Color color) =>
      _preferencesStore.writeSeedColor(color.toARGB32());

  Future<String?> loadToken() async {
    try {
      return await _secureTokenStore.readToken();
    } catch (_) {
      return null;
    }
  }

  Future<SaveTokenResult> saveToken(String input) async {
    final token = input.replaceAll(RegExp(r'\s+'), '');
    if (token.isEmpty) return SaveTokenResult.emptyInput;

    try {
      if (await _secureTokenStore.readToken() != null) {
        return SaveTokenResult.tokenAlreadyExists;
      }
      await _secureTokenStore.writeToken(token);
      return SaveTokenResult.saved;
    } catch (_) {
      return SaveTokenResult.storageError;
    }
  }

  Future<void> deleteToken() => _secureTokenStore.deleteToken();

  Future<void> resetSettings({required bool confirmTokenDeletion}) async {
    await _preferencesStore.clearUserPreferences();
    if (confirmTokenDeletion) {
      await _secureTokenStore.deleteToken();
    }
  }
}
