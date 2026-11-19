import 'package:flutter/services.dart';

import 'connectivity_monitor.dart';

class PlatformConnectivitySource implements ConnectivityStatusSource {
  PlatformConnectivitySource({
    EventChannel channel = const EventChannel('lerua_zakup/connectivity'),
  }) : _channel = channel;

  final EventChannel _channel;

  @override
  Stream<bool> get hasInternet => _channel
      .receiveBroadcastStream()
      .map((event) => event == true)
      .distinct();
}
