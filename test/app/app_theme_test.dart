import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lerua_zakup/app/app_theme.dart';

void main() {
  group('AppTheme', () {
    test('provides a light theme', () {
      expect(AppTheme.light.brightness, Brightness.light);
    });

    test('provides a dark theme', () {
      expect(AppTheme.dark.brightness, Brightness.dark);
    });

    testWidgets('system theme follows live platform brightness changes', (tester) async {
      var brightness = Brightness.light;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: ThemeMode.system,
          home: const SizedBox(),
        ),
      );
      expect(Theme.of(tester.element(find.byType(SizedBox))).brightness, brightness);

      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pump();
      brightness = Brightness.dark;
      expect(Theme.of(tester.element(find.byType(SizedBox))).brightness, brightness);
      tester.platformDispatcher.clearPlatformBrightnessTestValue();
    });
  });
}
