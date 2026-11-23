import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lerua_zakup/features/calendar/presentation/week_strip.dart';
import 'package:lerua_zakup/features/home/presentation/home_screen.dart';

void main() {
  final now = DateTime(2026, 11, 19);

  testWidgets('reserves a four-pixel indicator slot above the calendar', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeScreen(
            now: now,
            onOpenCalendar: () {},
            onOpenSettings: () {},
            onShowPlaceholder: (_) {},
          ),
        ),
      ),
    );

    final indicator = tester.getSize(
      find.byKey(const ValueKey('connectivity-indicator-slot')),
    );
    final calendar = tester.getTopLeft(find.byType(WeekStrip));
    expect(indicator.height, 4);
    expect(calendar.dy, greaterThanOrEqualTo(4));
  });

  testWidgets('shows the week before six equally styled text-only buttons', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeScreen(
            now: now,
            onOpenCalendar: () {},
            onOpenSettings: () {},
            onShowPlaceholder: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('Пн'), findsOneWidget);
    expect(find.text('Вс'), findsOneWidget);
    final labels = [
      'Закупка',
      'Заказ',
      'Перемещение',
      'Инвентаризация',
      'Прочие действия',
      'Настройки',
    ];
    for (final label in labels) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.byIcon(Icons.expand_more), findsOneWidget);
    final weekTop = tester.getTopLeft(find.byType(WeekStrip)).dy;
    final firstButtonTop = tester.getTopLeft(find.text('Закупка')).dy;
    expect(firstButtonTop, greaterThan(weekTop));
  });

  testWidgets('distributes all six buttons evenly in the remaining space', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeScreen(
            now: now,
            onOpenCalendar: () {},
            onOpenSettings: () {},
            onShowPlaceholder: (_) {},
          ),
        ),
      ),
    );

    final centers = [
      for (final label in [
        'Закупка',
        'Заказ',
        'Перемещение',
        'Инвентаризация',
        'Прочие действия',
        'Настройки',
      ])
        tester.getCenter(find.text(label)).dy,
    ];
    final gaps = [
      for (var i = 1; i < centers.length; i++) centers[i] - centers[i - 1],
    ];
    for (final gap in gaps.skip(1)) {
      expect(gap, closeTo(gaps.first, 2));
    }
  });

  testWidgets('opens the inventory flow from the home action', (tester) async {
    var opened = false;
    var placeholderShown = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeScreen(
            now: now,
            onOpenCalendar: () {},
            onOpenSettings: () {},
            onOpenInventory: () => opened = true,
            onShowPlaceholder: (_) => placeholderShown = true,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Инвентаризация'));
    expect(opened, isTrue);
    expect(placeholderShown, isFalse);
  });

  testWidgets('expands the full calendar from the control below the week', (
    tester,
  ) async {
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeScreen(
            now: now,
            onOpenCalendar: () => opened = true,
            onOpenSettings: () {},
            onShowPlaceholder: (_) {},
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('expand-calendar')));
    expect(opened, isTrue);
  });

  testWidgets(
    'updates the selected weekday without changing the displayed week',
    (tester) async {
      DateTime? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomeScreen(
              now: now,
              onOpenCalendar: () {},
              onOpenSettings: () {},
              onShowPlaceholder: (message) {},
              onDateSelected: (date) => selected = date,
            ),
          ),
        ),
      );

      await tester.tap(find.text('20'));
      expect(selected, DateTime(2026, 11, 20));
    },
  );
}
