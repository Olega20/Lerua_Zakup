import 'dart:async';

import 'package:flutter/services.dart';

import 'connectivity_monitor.dart';

class PlatformConnectivitySource implements ConnectivityStatusSource {
  PlatformConnectivitySource({
    this.channel = const EventChannel('lerua_zakup/connectivity'),
  });

  final EventChannel channel;

  @override
  Stream<bool> get hasInternet => channel
      .receiveBroadcastStream()
      .map((event) => event == true)
      .transform(
        StreamTransformer<bool, bool>.fromHandlers(
          handleError: (error, stackTrace, sink) => sink.add(false),
        ),
      )
      .distinct();
}
