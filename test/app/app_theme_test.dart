import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lerua_zakup/app/app_theme.dart';

void main() {
  test('provides a light Material 3 theme from the selected seed', () {
    const seed = Color(0xFF1565C0);
    final theme = AppTheme.light(seedColor: seed);
    expect(theme.brightness, Brightness.light);
    expect(theme.useMaterial3, isTrue);
    expect(
      theme.colorScheme.primary,
      isNot(AppTheme.light().colorScheme.primary),
    );
  });

  test('provides a dark Material 3 theme from the same selected seed', () {
    const seed = Color(0xFF1565C0);
    final theme = AppTheme.dark(seedColor: seed);
    expect(theme.brightness, Brightness.dark);
    expect(theme.useMaterial3, isTrue);
    expect(
      theme.colorScheme.primary,
      isNot(AppTheme.dark().colorScheme.primary),
    );
  });

  test('uses green as the default seed color', () {
    expect(AppTheme.defaultSeedColor, const Color(0xFF2E7D32));
  });
}