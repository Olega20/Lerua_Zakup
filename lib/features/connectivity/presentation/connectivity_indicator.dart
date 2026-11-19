import 'dart:async';

import 'package:flutter/material.dart';

import '../domain/connectivity_status.dart';

class ConnectivityIndicator extends StatefulWidget {
  const ConnectivityIndicator({super.key, required this.statuses});

  final Stream<ConnectivityStatus> statuses;

  @override
  State<ConnectivityIndicator> createState() => _ConnectivityIndicatorState();
}

class _ConnectivityIndicatorState extends State<ConnectivityIndicator> {
  StreamSubscription<ConnectivityStatus>? _subscription;
  ConnectivityStatus _status = ConnectivityStatus.offline;

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
    color: _status == ConnectivityStatus.online ? Colors.amber : Colors.red,
  );
}
