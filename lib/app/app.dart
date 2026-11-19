import 'package:flutter/material.dart';

import '../core/feedback/snackbar_service.dart';
import '../features/calendar/presentation/full_calendar_screen.dart';
import '../features/home/presentation/home_screen.dart';
import 'app_router.dart';
import 'app_theme.dart';

class LeruaZakupApp extends StatefulWidget {
  const LeruaZakupApp({super.key});

  @override
  State<LeruaZakupApp> createState() => _LeruaZakupAppState();
}

class _LeruaZakupAppState extends State<LeruaZakupApp> {
  final AppRouter _router = AppRouter();
  final SnackbarService _snackbarService = SnackbarService();

  void _openCalendar(BuildContext context) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => FullCalendarScreen(now: DateTime.now()),
      ),
    );
  }

  void _openSettings(BuildContext context) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const _SettingsPlaceholderScreen()),
    );
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Lerua Zakup',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    darkTheme: AppTheme.dark,
    themeMode: ThemeMode.light,
    navigatorKey: _router.navigatorKey,
    home: Builder(
      builder: (context) => Scaffold(
        body: HomeScreen(
          now: DateTime.now(),
          onOpenCalendar: () => _openCalendar(context),
          onOpenSettings: () => _openSettings(context),
          onShowPlaceholder: (message) =>
              _snackbarService.show(context, message),
        ),
      ),
    ),
    builder: (context, child) => Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _snackbarService.dismiss(),
      child: child ?? const SizedBox.shrink(),
    ),
  );
}

class _SettingsPlaceholderScreen extends StatelessWidget {
  const _SettingsPlaceholderScreen();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Настройки')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ListTile(
          title: const Text('Журнал склада'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Функция находится в разработке'),
              duration: Duration(seconds: 5),
              behavior: SnackBarBehavior.floating,
            ),
          ),
        ),
      ],
    ),
  );
}
