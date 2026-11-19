import 'dart:async';

import '../domain/connectivity_status.dart';

abstract interface class ConnectivityStatusSource {
  Stream<bool> get hasInternet;
}

class ConnectivityMonitor {
  ConnectivityMonitor({required this.source});

  final ConnectivityStatusSource source;

  Stream<ConnectivityStatus> get statuses => source.hasInternet
      .map(
        (available) =>
            available ? ConnectivityStatus.online : ConnectivityStatus.offline,
      )
      .distinct();
}
