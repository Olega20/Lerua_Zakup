import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lerua_zakup/core/feedback/snackbar_service.dart';

void main() {
  testWidgets('shows a snackbar at the bottom of the screen', (tester) async {
    final service = SnackbarService();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => service.show(context, 'Сообщение'),
                child: const Text('Показать'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Показать'));
    await tester.pump();
    expect(find.text('Сообщение'), findsOneWidget);
    final snackbar = tester.getRect(find.byType(SnackBar));
    final screenHeight = tester.view.physicalSize.height / tester.view.devicePixelRatio;
    expect(snackbar.bottom, lessThanOrEqualTo(screenHeight));
    expect(snackbar.bottom, greaterThan(screenHeight - 100));
  });

  testWidgets('automatically disappears after five seconds', (tester) async {
    final service = SnackbarService();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => service.show(context, 'Временное'),
              child: const Text('Показать'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Показать'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Временное'), findsNothing);
  });

  testWidgets('dismisses the snackbar after a tap anywhere on the screen', (tester) async {
    final service = SnackbarService();
    await tester.pumpWidget(
      Listener(
        onPointerDown: (_) => service.dismiss,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => service.show(context, 'Закрыть касанием'),
                child: const Text('Показать'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Показать'));
    await tester.pump();
    expect(find.text('Закрыть касанием'), findsOneWidget);
    await tester.tapAt(const Offset(20, 20));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Закрыть касанием'), findsNothing);
  });
}
