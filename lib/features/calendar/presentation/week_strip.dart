import 'package:flutter/material.dart';
import '../domain/calendar_date.dart';

class WeekStrip extends StatelessWidget {
  const WeekStrip({super.key, required this.now, required this.selectedDate, required this.onDateSelected});
  final DateTime now;
  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateSelected;

  @override
  Widget build(BuildContext context) {
    final days = CalendarDate.weekDays(now);
    final colors = Theme.of(context).colorScheme;
    return Row(children: [
      for (final day in days)
        Expanded(child: InkWell(
          onTap: () => onDateSelected(day),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 1),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(CalendarDate.weekdayShort(day.weekday), style: TextStyle(
                color: day.weekday >= DateTime.saturday ? colors.tertiary : colors.onSurfaceVariant,
                fontSize: 12,
              )),
              const SizedBox(height: 5),
              Container(
                width: 34, height: 34, alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: CalendarDate.sameDay(day, selectedDate) ? colors.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(17),
                ),
                child: Text('${day.day}', style: TextStyle(
                  color: CalendarDate.sameDay(day, selectedDate) ? colors.onPrimary :
                    day.weekday >= DateTime.saturday ? colors.tertiary : colors.onSurface,
                  fontWeight: CalendarDate.sameDay(day, selectedDate) ? FontWeight.w600 : FontWeight.normal,
                )),
              ),
            ]),
          ),
        )),
    ]);
  }
}
