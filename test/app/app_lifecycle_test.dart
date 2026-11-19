import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lerua_zakup/app/app_lifecycle.dart';
import 'package:lerua_zakup/app/app_router.dart';

class FakeSystemUiController implements SystemUiController {
  int portraitCalls = 0;
  int immersiveCalls = 0;

  @override
  Future<void> setPortraitOrientation() async {
    portraitCalls++;
  }

  @override
  Future<void> enableImmersiveMode() async {
    immersiveCalls++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('AppLifecycleController', () {
    test('configures portrait immersive mode on initialization', () async {
      final systemUi = FakeSystemUiController();
      final controller = AppLifecycleController(systemUi: systemUi);

      await controller.initialize();

      expect(systemUi.portraitCalls, 1);
      expect(systemUi.immersiveCalls, 1);
      controller.dispose();
    });

    test('reapplies system UI configuration when the app resumes', () async {
      final systemUi = FakeSystemUiController();
      final controller = AppLifecycleController(systemUi: systemUi);
      await controller.initialize();

      controller.didChangeAppLifecycleState(AppLifecycleState.inactive);
      expect(systemUi.immersiveCalls, 1);

      controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);

      expect(systemUi.portraitCalls, 2);
      expect(systemUi.immersiveCalls, 2);
      controller.dispose();
    });

    test('restores only a valid destination supplied by Android', () {
      expect(
        AppLifecycleController.destinationFromRestoration('settings'),
        AppDestination.settings,
      );
      expect(
        AppLifecycleController.destinationFromRestoration('fullCalendar'),
        AppDestination.fullCalendar,
      );
      expect(
        AppLifecycleController.destinationFromRestoration('unknown'),
        AppDestination.home,
      );
      expect(
        AppLifecycleController.destinationFromRestoration(null),
        AppDestination.home,
      );
    });

    test('a fresh launch without system state starts at Home', () {
      expect(
        AppLifecycleController.destinationFromRestoration(null),
        AppDestination.home,
      );
    });
  });

  group('HomeBackController', () {
    test(
      'shows confirmation first and exits on a second press within two seconds',
      () {
        final controller = HomeBackController();
        final first = DateTime(2026, 11, 19, 12);
        expect(
          controller.handleBack(first),
          HomeBackAction.showExitConfirmation,
        );
        expect(
          controller.handleBack(first.add(const Duration(milliseconds: 1999))),
          HomeBackAction.exit,
        );
      },
    );

    test('shows confirmation again after the two-second window', () {
      final controller = HomeBackController();
      final first = DateTime(2026, 11, 19, 12);
      expect(controller.handleBack(first), HomeBackAction.showExitConfirmation);
      expect(
        controller.handleBack(
          first.add(const Duration(seconds: 2, milliseconds: 1)),
        ),
        HomeBackAction.showExitConfirmation,
      );
    });
  });
}
