import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract interface class PreferencesStore {
  Future<ThemeMode?> readTheme();
  Future<void> writeTheme(ThemeMode mode);
  Future<void> clearUserPreferences();
}

class SharedPreferencesStore implements PreferencesStore {
  static const _themeKey = 'theme_mode';

  @override
  Future<ThemeMode?> readTheme() async {
    final preferences = await SharedPreferences.getInstance();
    final value = preferences.getString(_themeKey);
    for (final mode in ThemeMode.values) {
      if (mode.name == value) return mode;
    }
    return null;
  }

  @override
  Future<void> writeTheme(ThemeMode mode) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_themeKey, mode.name);
  }

  @override
  Future<void> clearUserPreferences() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.clear();
  }
}
