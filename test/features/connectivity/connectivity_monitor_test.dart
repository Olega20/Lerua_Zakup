import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lerua_zakup/features/connectivity/data/connectivity_monitor.dart';
import 'package:lerua_zakup/features/connectivity/domain/connectivity_status.dart';

class FakeConnectivityStatusSource implements ConnectivityStatusSource {
  final controller = StreamController<bool>.broadcast();
  int subscriptionCount = 0;

  @override
  Stream<bool> get hasInternet => controller.stream.transform(
    StreamTransformer<bool, bool>.fromHandlers(
      handleData: (value, sink) {
        subscriptionCount++;
        sink.add(value);
      },
    ),
  );

  Future<void> dispose() => controller.close();
}

void main() {
  group('ConnectivityMonitor', () {
    late FakeConnectivityStatusSource source;
    late ConnectivityMonitor monitor;

    setUp(() {
      source = FakeConnectivityStatusSource();
      monitor = ConnectivityMonitor(source: source);
    });

    tearDown(() => source.dispose());

    test('maps no validated internet to Offline', () async {
      final result = expectLater(
        monitor.statuses,
        emits(ConnectivityStatus.offline),
      );
      source.controller.add(false);
      await result;
    });

    test('maps validated internet to Online (yellow state)', () async {
      final result = expectLater(
        monitor.statuses,
        emits(ConnectivityStatus.online),
      );
      source.controller.add(true);
      await result;
    });

    test('immediately reports loss of internet and recovers online', () async {
      final result = expectLater(
        monitor.statuses,
        emitsInOrder([
          ConnectivityStatus.online,
          ConnectivityStatus.offline,
          ConnectivityStatus.online,
        ]),
      );
      source.controller
        ..add(true)
        ..add(false)
        ..add(true);
      await result;
    });

    test('suppresses duplicate connectivity events', () async {
      final result = expectLater(
        monitor.statuses,
        emitsInOrder([ConnectivityStatus.online, emitsDone]),
      );
      source.controller
        ..add(true)
        ..add(true);
      await source.controller.close();
      await result;
    });

    test('does not issue HTTP or MoySklad API requests', () async {
      final result = expectLater(
        monitor.statuses,
        emits(ConnectivityStatus.online),
      );
      source.controller.add(true);
      await result;
      expect(source.subscriptionCount, 1);
    });
  });
}
