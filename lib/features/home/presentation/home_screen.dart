import 'package:flutter/material.dart';

import '../../calendar/presentation/week_strip.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.now,
    required this.onOpenCalendar,
    required this.onOpenSettings,
    required this.onShowPlaceholder,
    this.onDateSelected,
  });

  final DateTime now;
  final VoidCallback onOpenCalendar;
  final VoidCallback onOpenSettings;
  final ValueChanged<String> onShowPlaceholder;
  final ValueChanged<DateTime>? onDateSelected;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with RestorationMixin {
  late DateTime _selectedDate;
  late final RestorableString _restoredSelectedDate =
      RestorableString(_today.toIso8601String());

  @override
  String? get restorationId => 'home_screen';

  @override
  void restoreState(RestorationBucket? oldBucket, bool initialRestore) {
    registerForRestoration(_restoredSelectedDate, 'selected_date');
    _selectedDate = DateTime.tryParse(_restoredSelectedDate.value) ?? _today;
  }

  static const _businessActions = [
    'Закупка',
    'Заказ',
    'Перемещение',
    'Инвентаризация',
    'Прочие действия',
  ];

  @override
  void initState() {
    super.initState();
    _selectedDate = _today;
  }

  DateTime get _today =>
      DateTime(widget.now.year, widget.now.month, widget.now.day);

  void _selectDate(DateTime date) {
    setState(() {
      _selectedDate = date;
      _restoredSelectedDate.value = date.toIso8601String();
    });
    widget.onDateSelected?.call(date);
  }

  void _openCalendar() {
    setState(() {
      _selectedDate = _today;
      _restoredSelectedDate.value = _today.toIso8601String();
    });
    widget.onOpenCalendar();
  }

  void _openSettings() {
    setState(() {
      _selectedDate = _today;
      _restoredSelectedDate.value = _today.toIso8601String();
    });
    widget.onOpenSettings();
  }

  @override
  void dispose() {
    _restoredSelectedDate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SafeArea(
      child: Column(
        children: [
          const SizedBox(
            key: ValueKey('connectivity-indicator-slot'),
            height: 4,
            width: double.infinity,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: WeekStrip(
              now: widget.now,
              selectedDate: _selectedDate,
              onDateSelected: _selectDate,
            ),
          ),
          IconButton(
            key: const ValueKey('expand-calendar'),
            tooltip: 'Открыть календарь',
            visualDensity: VisualDensity.compact,
            onPressed: _openCalendar,
            icon: const Icon(Icons.expand_more),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 2, 10, 8),
              child: Column(
                children: [
                  for (final label in _businessActions)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: _HomeActionButton(
                          label: label,
                          onPressed: () => widget.onShowPlaceholder(
                            'Функция находится в разработке',
                          ),
                        ),
                      ),
                    ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: _HomeActionButton(
                        label: 'Настройки',
                        onPressed: _openSettings,
                        foregroundColor: colors.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeActionButton extends StatelessWidget {
  const _HomeActionButton({
    required this.label,
    required this.onPressed,
    this.foregroundColor,
  });

  final String label;
  final VoidCallback onPressed;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox.expand(
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: foregroundColor ?? colors.onSurface,
          backgroundColor: colors.surface,
          side: BorderSide(color: colors.outlineVariant, width: 0.8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
          textStyle: Theme.of(context).textTheme.titleMedium,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        ),
        child: Text(label, textAlign: TextAlign.center),
      ),
    );
  }
}
