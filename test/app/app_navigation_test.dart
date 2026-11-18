import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lerua_zakup/app/app_router.dart';

void main() {
  testWidgets('router opens a destination and returns to the previous screen', (tester) async {
    final router = AppRouter();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: router.navigatorKey,
        onGenerateRoute: router.onGenerateRoute,
        home: const Scaffold(body: Text('Home screen')),
      ),
    );

    router.push(AppDestination.settings);
    await tester.pumpAndSettle();
    expect(find.text('Настройки'), findsOneWidget);

    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('Home screen'), findsOneWidget);
  });

  testWidgets('pushing an already active destination does not duplicate it', (tester) async {
    final router = AppRouter();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: router.navigatorKey,
        onGenerateRoute: router.onGenerateRoute,
        home: const Scaffold(body: Text('Home screen')),
      ),
    );

    router.push(AppDestination.settings);
    await tester.pumpAndSettle();
    router.push(AppDestination.settings);
    await tester.pumpAndSettle();

    expect(find.text('Настройки'), findsOneWidget);
    expect(router.activeDestinations, [AppDestination.home, AppDestination.settings]);
  });

  testWidgets('router replaces a destination when navigating between sections', (tester) async {
    final router = AppRouter();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: router.navigatorKey,
        onGenerateRoute: router.onGenerateRoute,
        home: const Scaffold(body: Text('Home screen')),
      ),
    );

    router.replace(AppDestination.purchase);
    await tester.pumpAndSettle();
    expect(find.text('Закупка'), findsOneWidget);
    expect(find.text('Home screen'), findsNothing);
    expect(router.activeDestinations, [AppDestination.purchase]);
  });
}
