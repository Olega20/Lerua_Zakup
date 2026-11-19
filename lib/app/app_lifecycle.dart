import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_router.dart';

abstract interface class SystemUiController {
  Future<void> setPortraitOrientation();
  Future<void> enableImmersiveMode();
}

class FlutterSystemUiController implements SystemUiController {
  @override
  Future<void> setPortraitOrientation() => SystemChrome.setPreferredOrientations(
    const [DeviceOrientation.portraitUp],
  );

  @override
  Future<void> enableImmersiveMode() => SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.immersiveSticky,
  );
}

class AppLifecycleController with WidgetsBindingObserver {
  AppLifecycleController({required SystemUiController systemUi})
    : _systemUi = systemUi;

  final SystemUiController _systemUi;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    WidgetsBinding.instance.addObserver(this);
    await _applySystemUi();
  }

  Future<void> _applySystemUi() async {
    await _systemUi.setPortraitOrientation();
    await _systemUi.enableImmersiveMode();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _applySystemUi();
    }
  }

  static AppDestination destinationFromRestoration(String? value) {
    for (final destination in AppDestination.values) {
      if (destination.name == value) return destination;
    }
    return AppDestination.home;
  }

  void dispose() {
    if (_initialized) {
      WidgetsBinding.instance.removeObserver(this);
      _initialized = false;
    }
  }
}
