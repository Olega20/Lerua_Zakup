import 'package:flutter/material.dart';

class SnackbarService {
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

  void dismiss() {
    _messenger?.hideCurrentSnackBar();
  }
}
