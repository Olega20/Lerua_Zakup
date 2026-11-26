import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract interface class PreferencesStore {
  Future<ThemeMode?> readTheme();
  Future<void> writeTheme(ThemeMode mode);
  Future<int?> readSeedColor();
  Future<void> writeSeedColor(int argb);
  Future<void> clearUserPreferences();
}

class SharedPreferencesStore implements PreferencesStore {
  static const _themeKey = 'theme_mode';
  static const _seedColorKey = 'seed_color';

  @override
  Future<ThemeMode?> readTheme() async {
    final preferences = await SharedPreferences.getInstance();
    final value = preferences.getString(_themeKey);
    if (value == null) return null;
    for (final mode in ThemeMode.values) {
      if (mode.name == value) return mode;
    }
    throw FormatException('Unsupported saved theme mode');
  }

  @override
  Future<void> writeTheme(ThemeMode mode) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_themeKey, mode.name);
  }

  @override
  Future<int?> readSeedColor() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getInt(_seedColorKey);
  }

  @override
  Future<void> writeSeedColor(int argb) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(_seedColorKey, argb);
  }

  @override
  Future<void> clearUserPreferences() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_themeKey);
    await preferences.remove(_seedColorKey);
  }
}
