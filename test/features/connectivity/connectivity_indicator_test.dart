import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lerua_zakup/features/connectivity/domain/connectivity_status.dart';
import 'package:lerua_zakup/features/connectivity/presentation/connectivity_indicator.dart';

void main() {
  testWidgets('starts red while internet status is not yet confirmed', (
    tester,
  ) async {
    final statuses = StreamController<ConnectivityStatus>.broadcast();
    addTearDown(statuses.close);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ConnectivityIndicator(statuses: statuses.stream)),
      ),
    );

    final indicator = tester.widget<Container>(
      find.byKey(const ValueKey('connectivity-indicator')),
    );
    expect(indicator.color, Colors.red);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('connectivity-indicator')))
          .height,
      4,
    );
  });

  testWidgets('uses yellow online and immediately changes to red offline', (
    tester,
  ) async {
    final statuses = StreamController<ConnectivityStatus>.broadcast();
    addTearDown(statuses.close);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ConnectivityIndicator(statuses: statuses.stream)),
      ),
    );

    statuses.add(ConnectivityStatus.online);
    await tester.pump();
    expect(
      tester
          .widget<Container>(
            find.byKey(const ValueKey('connectivity-indicator')),
          )
          .color,
      Colors.amber,
    );

    statuses.add(ConnectivityStatus.offline);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Container>(
            find.byKey(const ValueKey('connectivity-indicator')),
          )
          .color,
      Colors.red,
    );
  });

  testWidgets('never shows green before API confirmation is implemented', (
    tester,
  ) async {
    final statuses = StreamController<ConnectivityStatus>.broadcast();
    addTearDown(statuses.close);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ConnectivityIndicator(statuses: statuses.stream)),
      ),
    );

    statuses.add(ConnectivityStatus.online);
    await tester.pump();
    final color = tester
        .widget<Container>(find.byKey(const ValueKey('connectivity-indicator')))
        .color;
    expect(color, isNot(Colors.green));
  });
}
