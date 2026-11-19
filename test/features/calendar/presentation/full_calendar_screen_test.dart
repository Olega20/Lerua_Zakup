import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lerua_zakup/features/calendar/presentation/full_calendar_screen.dart';

void main() {
  final now = DateTime(2026, 11, 19);

  Future<void> pumpCalendar(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(home: FullCalendarScreen(now: now)));
  }

  testWidgets('opens on the current month and selects today', (tester) async {
    await pumpCalendar(tester);

    expect(find.text('Ноябрь'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('calendar-date-2026-11-19')),
      findsOneWidget,
    );
    expect(find.text('Нет операций за этот день'), findsOneWidget);
  });

  testWidgets('shows weekday headings and only the required month rows', (
    tester,
  ) async {
    await pumpCalendar(tester);

    for (final label in ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith(
              'calendar-week-row-',
            ),
      ),
      findsNWidgets(6),
    );
  });

  testWidgets('selecting an adjacent-month date selects it and changes month', (
    tester,
  ) async {
    await pumpCalendar(tester);

    await tester.tap(find.byKey(const ValueKey('calendar-date-2026-12-01')));
    await tester.pumpAndSettle();

    expect(find.text('Декабрь'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('calendar-date-2026-12-01')),
      findsOneWidget,
    );
  });

  testWidgets(
    'swiping changes the displayed month without changing selection',
    (tester) async {
      await pumpCalendar(tester);

      await tester.drag(
        find.byKey(const ValueKey('calendar-month-grid')),
        const Offset(-400, 0),
      );
      await tester.pumpAndSettle();

      expect(find.text('Декабрь'), findsOneWidget);
      await tester.drag(
        find.byKey(const ValueKey('calendar-month-grid')),
        const Offset(400, 0),
      );
      await tester.pumpAndSettle();
      expect(find.text('Ноябрь'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('calendar-date-2026-11-19')),
        findsOneWidget,
      );
    },
  );
}
