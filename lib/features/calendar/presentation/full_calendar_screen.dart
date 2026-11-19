import 'package:flutter/material.dart';

import '../domain/calendar_date.dart';

class FullCalendarScreen extends StatefulWidget {
  const FullCalendarScreen({super.key, required this.now});
  final DateTime now;
  @override
  State<FullCalendarScreen> createState() => _FullCalendarScreenState();
}

class _FullCalendarScreenState extends State<FullCalendarScreen>
    with RestorationMixin {
  late DateTime _selectedDate;
  late DateTime _visibleMonth;
  double _horizontalDrag = 0;
  late final RestorableString _restoredSelectedDate =
      RestorableString(widget.now.toIso8601String());
  late final RestorableString _restoredVisibleMonth = RestorableString(
    DateTime(widget.now.year, widget.now.month, 1).toIso8601String(),
  );

  @override
  String? get restorationId => 'full_calendar_screen';

  @override
  void restoreState(RestorationBucket? oldBucket, bool initialRestore) {
    registerForRestoration(_restoredSelectedDate, 'selected_date');
    registerForRestoration(_restoredVisibleMonth, 'visible_month');
    _selectedDate = CalendarDate.dateOnly(
      DateTime.tryParse(_restoredSelectedDate.value) ?? widget.now,
    );
    final restoredMonth =
        DateTime.tryParse(_restoredVisibleMonth.value) ?? widget.now;
    _visibleMonth = DateTime(restoredMonth.year, restoredMonth.month, 1);
  }

  @override
  void initState() {
    super.initState();
    _selectedDate = CalendarDate.today(widget.now);
    _visibleMonth = DateTime(widget.now.year, widget.now.month, 1);
  }

  void _changeMonth(int amount) => setState(() {
    _visibleMonth = CalendarDate.addMonths(_visibleMonth, amount);
    _restoredVisibleMonth.value = _visibleMonth.toIso8601String();
  });

  void _selectDate(DateTime date) {
    if (CalendarDate.sameDay(date, _selectedDate)) return;
    setState(() {
      _selectedDate = CalendarDate.dateOnly(date);
      _restoredSelectedDate.value = _selectedDate.toIso8601String();
      if (_selectedDate.month != _visibleMonth.month ||
          _selectedDate.year != _visibleMonth.year) {
        _visibleMonth = DateTime(_selectedDate.year, _selectedDate.month, 1);
        _restoredVisibleMonth.value = _visibleMonth.toIso8601String();
      }
    });
  }

  @override
  void dispose() {
    _restoredSelectedDate.dispose();
    _restoredVisibleMonth.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rows = CalendarDate.monthGrid(
      _visibleMonth.year,
      _visibleMonth.month,
    );
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Назад',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          CalendarDate.monthTitle(
            _visibleMonth.year,
            _visibleMonth.month,
            currentYear: widget.now.year,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  for (var weekday = 1; weekday <= 7; weekday++)
                    Expanded(
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            CalendarDate.weekdayShort(weekday),
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: weekday >= DateTime.saturday
                                  ? colors.tertiary
                                  : colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              key: const ValueKey('calendar-month-grid'),
              onHorizontalDragStart: (_) => _horizontalDrag = 0,
              onHorizontalDragUpdate: (details) =>
                  _horizontalDrag += details.delta.dx,
              onHorizontalDragEnd: (_) {
                if (_horizontalDrag.abs() >= 50) {
                  _changeMonth(_horizontalDrag < 0 ? 1 : -1);
                }
                _horizontalDrag = 0;
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var rowIndex = 0; rowIndex < rows.length; rowIndex++)
                      Row(
                        key: ValueKey('calendar-week-row-$rowIndex'),
                        children: [
                          for (final day in rows[rowIndex])
                            Expanded(
                              child: _CalendarDay(
                                date: day,
                                selectedDate: _selectedDate,
                                today: CalendarDate.today(widget.now),
                                visibleMonth: _visibleMonth,
                                onTap: () => _selectDate(day),
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: Center(
                child: Text(
                  'Нет операций за этот день',
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CalendarDay extends StatelessWidget {
  const _CalendarDay({
    required this.date,
    required this.selectedDate,
    required this.today,
    required this.visibleMonth,
    required this.onTap,
  });
  final DateTime date, selectedDate, today, visibleMonth;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isSelected = CalendarDate.sameDay(date, selectedDate);
    final isToday = CalendarDate.sameDay(date, today);
    final isCurrentMonth =
        date.month == visibleMonth.month && date.year == visibleMonth.year;
    final isWeekend = date.weekday >= DateTime.saturday;
    final dateKey =
        'calendar-date-${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    return AspectRatio(
      aspectRatio: 1.6,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: InkWell(
          key: ValueKey(dateKey),
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              color: isSelected ? colors.primary : Colors.transparent,
              shape: BoxShape.circle,
              border: isToday && !isSelected
                  ? Border.all(color: colors.primary, width: 1)
                  : null,
            ),
            alignment: Alignment.center,
            child: Text(
              '${date.day}',
              style: TextStyle(
                color: isSelected
                    ? colors.onPrimary
                    : !isCurrentMonth
                    ? colors.onSurface.withValues(alpha: 0.32)
                    : isWeekend
                    ? colors.tertiary
                    : colors.onSurface,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }
}