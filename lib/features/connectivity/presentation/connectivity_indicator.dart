import 'dart:async';

import 'package:flutter/material.dart';

import '../domain/api_connection_state.dart';

class ConnectivityIndicator extends StatefulWidget {
  const ConnectivityIndicator({super.key, required this.statuses});

  final Stream<ApiConnectionState> statuses;

  @override
  State<ConnectivityIndicator> createState() => _ConnectivityIndicatorState();
}

class _ConnectivityIndicatorState extends State<ConnectivityIndicator> {
  StreamSubscription<ApiConnectionState>? _subscription;
  ApiConnectionState _status = ApiConnectionState.offline;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(covariant ConnectivityIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.statuses != widget.statuses) _listen();
  }

  void _listen() {
    _subscription?.cancel();
    _subscription = widget.statuses.listen((status) {
      if (mounted && status != _status) setState(() => _status = status);
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('connectivity-indicator'),
    height: 4,
    width: double.infinity,
    color: switch (_status) {
      ApiConnectionState.offline => Colors.red,
      ApiConnectionState.connected => Colors.green,
      ApiConnectionState.checking ||
      ApiConnectionState.unavailable => Colors.amber,
    },
  );
}
