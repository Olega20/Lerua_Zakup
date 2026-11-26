import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lerua_zakup/app/app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'uses an Android restoration scope and restorable calendar route',
    (tester) async {
      await tester.pumpWidget(
        const LeruaZakupApp(
          appVersionOverride: '1.0.0+1',
          startApiTaskDispatcher: false,
        ),
      );

      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.restorationScopeId, 'lerua_zakup_app');

      await tester.tap(find.byKey(const ValueKey('expand-calendar')));
      await tester.pumpAndSettle();

      expect(find.text('Нет операций за этот день'), findsOneWidget);
    },
  );

  testWidgets('a fresh app instance without restoration starts on Home', (
    tester,
  ) async {
    await tester.pumpWidget(
      const LeruaZakupApp(
        appVersionOverride: '1.0.0+1',
        startApiTaskDispatcher: false,
      ),
    );

    expect(find.text('Закупка'), findsOneWidget);
    expect(find.text('Настройки'), findsOneWidget);
    expect(find.text('Нет операций за этот день'), findsNothing);
  });

  testWidgets('Home confirms exit and a second Back within two seconds exits', (
    tester,
  ) async {
    var exitCalls = 0;
    await tester.pumpWidget(
      LeruaZakupApp(
        startApiTaskDispatcher: false,
        appVersionOverride: '1.0.0+1',
        onExitRequested: () => exitCalls++,
      ),
    );

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Выйти?'), findsOneWidget);
    expect(exitCalls, 0);

    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(find.text('Выйти?'), findsNothing);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(exitCalls, 1);
  });
}
