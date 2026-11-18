import 'package:flutter/material.dart';

import '../core/feedback/snackbar_service.dart';
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

  @override
  Widget build(BuildContext context) => Listener(
        onPointerDown: (_) => _snackbarService.dismiss,
        child: MaterialApp(
        title: 'Lerua Zakup',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.light,
        navigatorKey: _router.navigatorKey,
        onGenerateRoute: _router.onGenerateRoute,
        home: const _InitialHomeScreen(),
        ),
      );
}

class _InitialHomeScreen extends StatelessWidget {
  const _InitialHomeScreen();

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(child: Text('Lerua Zakup')),
      );
}
