import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lerua_zakup/app/app_theme.dart';

void main() {
  test('provides a light theme', () {
    expect(AppTheme.light.brightness, Brightness.light);
  });

  test('provides a dark theme', () {
    expect(AppTheme.dark.brightness, Brightness.dark);
  });

  test('system theme mode is supported by Flutter', () {
    expect(ThemeMode.values, contains(ThemeMode.system));
  });
}
