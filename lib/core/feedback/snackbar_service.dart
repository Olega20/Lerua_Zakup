import 'package:material_ui/material_ui.dart';

class SnackbarService {
  final GlobalKey<ScaffoldMessengerState> messengerKey =
      GlobalKey<ScaffoldMessengerState>();
  ScaffoldMessengerState? _messenger;

  void show(BuildContext context, String message) {
    _messenger = ScaffoldMessenger.of(context);
    _messenger!
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
        ),
      );
  }

  void showGlobal(String message) {
    final messenger = messengerKey.currentState;
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
        ),
      );
  }

  void dismiss() {
    _messenger?.removeCurrentSnackBar();
  }
}
