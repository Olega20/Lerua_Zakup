import 'package:flutter/material.dart';

abstract final class AppTheme {
  static const Color defaultSeedColor = Color(0xFF2E7D32);

  static ThemeData light({Color seedColor = defaultSeedColor}) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.light,
    );
    return ThemeData(
      brightness: Brightness.light,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      useMaterial3: true,
    );
  }

  static ThemeData dark({Color seedColor = defaultSeedColor}) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.dark,
    );
    return ThemeData(
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      useMaterial3: true,
    );
  }
}
