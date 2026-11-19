import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lerua_zakup/app/app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('uses an Android restoration scope and restorable calendar route', (
    tester,
  ) async {
    await tester.pumpWidget(
      const LeruaZakupApp(appVersionOverride: '1.0.0+1'),
    );

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.restorationScopeId, 'lerua_zakup_app');

    await tester.tap(find.byKey(const ValueKey('expand-calendar')));
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
