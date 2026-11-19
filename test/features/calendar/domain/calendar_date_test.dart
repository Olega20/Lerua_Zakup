import 'package:flutter_test/flutter_test.dart';
import 'package:lerua_zakup/features/calendar/domain/calendar_date.dart';

void main() {
  group('CalendarDate.today', () {
    test('returns the local date without its time component', () {
      expect(
        CalendarDate.today(DateTime(2026, 11, 19, 23, 58)),
        DateTime(2026, 11, 19),
      );
    });
  });

  group('CalendarDate.weekDays', () {
    test('returns seven dates from Monday through Sunday', () {
      expect(CalendarDate.weekDays(DateTime(2026, 11, 19)), [
        DateTime(2026, 11, 16),
        DateTime(2026, 11, 17),
        DateTime(2026, 11, 18),
        DateTime(2026, 11, 19),
        DateTime(2026, 11, 20),
        DateTime(2026, 11, 21),
        DateTime(2026, 11, 22),
      ]);
    });
  });

  group('CalendarDate.monthGrid', () {
    test('starts weeks on Monday and includes adjacent-month dates', () {
      final grid = CalendarDate.monthGrid(2026, 11);
      expect(grid.first.first, DateTime(2026, 10, 26));
      expect(grid.first[0].weekday, DateTime.monday);
      expect(grid.last.last, DateTime(2026, 12, 6));
      expect(grid.last.last.weekday, DateTime.sunday);
    });

    test('uses only the number of rows required by the month', () {
      expect(CalendarDate.monthGrid(2021, 2), hasLength(4));
      expect(CalendarDate.monthGrid(2024, 2), hasLength(5));
      expect(CalendarDate.monthGrid(2021, 5), hasLength(6));
    });

    test('handles leap day', () {
      final dates = CalendarDate.monthGrid(2024, 2).expand((week) => week);
      expect(dates, contains(DateTime(2024, 2, 29)));
    });
  });

  group('CalendarDate formatting', () {
    test('formats dates in Russian DD.MM.YYYY format', () {
      expect(CalendarDate.formatDate(DateTime(2026, 3, 7)), '07.03.2026');
    });

    test('uses Russian short weekday names with Monday first', () {
      expect(
        List.generate(7, (index) => CalendarDate.weekdayShort(index + 1)),
        ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'],
      );
    });

    test('formats month title and adds year only for another year', () {
      expect(CalendarDate.monthTitle(2026, 11, currentYear: 2026), 'Ноябрь');
      expect(
        CalendarDate.monthTitle(2025, 11, currentYear: 2026),
        'Ноябрь 2025',
      );
    });
  });
}
