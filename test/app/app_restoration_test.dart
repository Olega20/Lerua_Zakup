import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lerua_zakup/app/app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('restores the open calendar route from Android restoration data', (
    tester,
  ) async {
    final restorationTester = RestorationTester(tester);
    await restorationTester.pumpWidget(
      const LeruaZakupApp(appVersionOverride: '1.0.0+1'),
    );

    await tester.tap(find.byKey(const ValueKey('expand-calendar')));
    await tester.pumpAndSettle();
    expect(find.text('Нет операций за этот день'), findsOneWidget);

    await restorationTester.restore();
    await tester.pumpAndSettle();

    expect(find.text('Нет операций за этот день'), findsOneWidget);
  });

  testWidgets('a fresh app instance without restoration starts on Home', (
    tester,
  ) async {
    await tester.pumpWidget(
      const LeruaZakupApp(appVersionOverride: '1.0.0+1'),
    );

    expect(find.text('Закупка'), findsOneWidget);
    expect(find.text('Настройки'), findsOneWidget);
    expect(find.text('Нет операций за этот день'), findsNothing);
  });
}
