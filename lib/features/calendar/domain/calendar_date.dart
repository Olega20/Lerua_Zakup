abstract final class CalendarDate {
  static const List<String> _weekdays = [
    'Пн',
    'Вт',
    'Ср',
    'Чт',
    'Пт',
    'Сб',
    'Вс',
  ];
  static const List<String> _months = [
    'Январь',
    'Февраль',
    'Март',
    'Апрель',
    'Май',
    'Июнь',
    'Июль',
    'Август',
    'Сентябрь',
    'Октябрь',
    'Ноябрь',
    'Декабрь',
  ];

  static DateTime today(DateTime now) => DateTime(now.year, now.month, now.day);
  static DateTime dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  static List<DateTime> weekDays(DateTime date) {
    final day = dateOnly(date);
    final monday = day.subtract(Duration(days: day.weekday - DateTime.monday));
    return List<DateTime>.generate(
      7,
      (index) => monday.add(Duration(days: index)),
    );
  }

  static List<List<DateTime>> monthGrid(int year, int month) {
    final first = DateTime(year, month, 1);
    final start = first.subtract(
      Duration(days: first.weekday - DateTime.monday),
    );
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final rowCount = ((first.weekday - 1 + daysInMonth) / 7).ceil();
    return List<List<DateTime>>.generate(
      rowCount,
      (row) => List<DateTime>.generate(
        7,
        (column) => start.add(Duration(days: row * 7 + column)),
      ),
    );
  }

  static String formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
  static String weekdayShort(int weekday) => _weekdays[weekday - 1];

  static String monthTitle(int year, int month, {required int currentYear}) {
    final name = _months[month - 1];
    return year == currentYear ? name : '$name $year';
  }

  static bool sameDay(DateTime first, DateTime second) =>
      first.year == second.year &&
      first.month == second.month &&
      first.day == second.day;

  static DateTime addMonths(DateTime date, int amount) =>
      DateTime(date.year, date.month + amount, 1);
}
