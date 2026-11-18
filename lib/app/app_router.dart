import 'package:flutter/material.dart';

enum AppDestination {
  home,
  fullCalendar,
  settings,
  purchase,
  order,
  transfer,
  inventory,
  otherActions,
  warehouseLog,
}

extension AppDestinationTitle on AppDestination {
  String get title => switch (this) {
        AppDestination.home => 'Главная',
        AppDestination.fullCalendar => 'Календарь',
        AppDestination.settings => 'Настройки',
        AppDestination.purchase => 'Закупка',
        AppDestination.order => 'Заказ',
        AppDestination.transfer => 'Перемещение',
        AppDestination.inventory => 'Инвентаризация',
        AppDestination.otherActions => 'Прочие действия',
        AppDestination.warehouseLog => 'Журнал склада',
      };
}

class AppRouter {
  AppRouter() : _stack = [AppDestination.home];

  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  final List<AppDestination> _stack;

  List<AppDestination> get activeDestinations => List.unmodifiable(_stack);

  Route<dynamic> onGenerateRoute(RouteSettings settings) {
    final destination = settings.arguments is AppDestination
        ? settings.arguments! as AppDestination
        : AppDestination.home;
    return MaterialPageRoute<void>(
      settings: settings,
      builder: (_) => DestinationPlaceholder(destination: destination),
    );
  }

  void push(AppDestination destination) {
    if (_stack.last == destination) return;
    _stack.add(destination);
    navigatorKey.currentState
        ?.pushNamed<void>('/${destination.name}', arguments: destination)
        .then((_) {
      if (_stack.length > 1 && _stack.last == destination) {
        _stack.removeLast();
      }
    });
  }

  void replace(AppDestination destination) {
    if (_stack.last == destination) return;
    if (_stack.length > 1) {
      _stack.removeLast();
    }
    _stack.add(destination);
    navigatorKey.currentState
        ?.pushReplacementNamed<void, void>('/${destination.name}', arguments: destination)
        .then((_) {
      if (_stack.length > 1 && _stack.last == destination) {
        _stack.removeLast();
      }
    });
  }

  void pop<T extends Object?>([T? result]) {
    if (_stack.length > 1) {
      navigatorKey.currentState?.pop<T>(result);
    }
  }
}

class DestinationPlaceholder extends StatelessWidget {
  const DestinationPlaceholder({super.key, required this.destination});

  final AppDestination destination;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(destination.title)),
        body: const Center(child: Text('Функция находится в разработке')),
      );
}
