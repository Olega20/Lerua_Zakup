import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lerua_zakup/features/calendar/presentation/week_strip.dart';

void main() {
  final now = DateTime(2026, 11, 19);

  Widget buildSubject({
    DateTime? selectedDate,
    ValueChanged<DateTime>? onDateSelected,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: WeekStrip(
          now: now,
          selectedDate: selectedDate ?? now,
          onDateSelected: onDateSelected ?? (_) {},
        ),
      ),
    );
  }

  testWidgets('shows the current Monday-to-Sunday week', (tester) async {
    await tester.pumpWidget(buildSubject());

    for (final label in ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс']) {
      expect(find.text(label), findsOneWidget);
    }
    for (final day in ['16', '17', '18', '19', '20', '21', '22']) {
      expect(find.text(day), findsOneWidget);
    }
  });

  testWidgets('selecting a day reports its complete date', (tester) async {
    DateTime? selected;
    await tester.pumpWidget(
      buildSubject(onDateSelected: (date) => selected = date),
    );

    await tester.tap(find.text('20'));
    expect(selected, DateTime(2026, 11, 20));
  });

  testWidgets('renders seven equal-width day cells', (tester) async {
    await tester.pumpWidget(buildSubject());
    final cells = tester.widgetList<Expanded>(find.byType(Expanded));
    expect(cells.length, 7);
  });
}
