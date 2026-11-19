import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lerua_zakup/core/storage/secure_token_store.dart';
import 'package:lerua_zakup/features/connectivity/data/moysklad_api_client.dart';
import 'package:lerua_zakup/features/connectivity/data/moysklad_api_manager.dart';
import 'package:lerua_zakup/features/connectivity/domain/api_connection_state.dart';

class FakeSecureTokenStore implements SecureTokenStore {
  String? token;
  @override
  Future<String?> readToken() async => token;
  @override
  Future<void> writeToken(String value) async => token = value;
  @override
  Future<void> deleteToken() async => token = null;
}

class FakeMoySkladTransport implements MoySkladHttpTransport {
  FakeMoySkladTransport(this.handler);
  final Future<MoySkladHttpResponse> Function() handler;
  int calls = 0;

  @override
  Future<MoySkladHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
  }) {
    calls++;
    return handler();
  }
}

class FakePeriodicTimer implements Timer {
  FakePeriodicTimer(this.callback);
  final void Function() callback;
  bool _active = true;
  @override
  bool get isActive => _active;
  @override
  int get tick => 0;
  @override
  void cancel() => _active = false;
  void fire() {
    if (_active) callback();
  }
}

void main() {
  group('MoySkladApiManager', () {
    late StreamController<bool> internet;
    late FakeSecureTokenStore tokenStore;
    late FakeMoySkladTransport transport;
    late List<FakePeriodicTimer> timers;
    late MoySkladApiManager manager;

    setUp(() {
      internet = StreamController<bool>.broadcast();
      tokenStore = FakeSecureTokenStore()..token = 'token';
      transport = FakeMoySkladTransport(
        () async => const MoySkladHttpResponse(statusCode: 200, body: '{}'),
      );
      timers = [];
      var now = DateTime(2026, 11, 19);
      manager = MoySkladApiManager(
        tokenStore: tokenStore,
        apiClient: MoySkladApiClient(transport: transport),
        internet: internet.stream,
        clock: () => now,
        periodicTimer: (duration, callback) {
          final timer = FakePeriodicTimer(callback);
          timers.add(timer);
          return timer;
        },
      );
    });

    tearDown(() async {
      await manager.dispose();
      await internet.close();
    });

    test('does not call API until internet is available', () async {
      await manager.start();
      expect(transport.calls, 0);
      internet.add(true);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(transport.calls, 1);
      expect(manager.currentState, ApiConnectionState.connected);
    });

    test('does not send a request without a saved token', () async {
      tokenStore.token = null;
      await manager.start();
      internet.add(true);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(transport.calls, 0);
      expect(manager.currentState, ApiConnectionState.unavailable);
    });

    test('loss of internet invalidates a late successful response', () async {
      final completer = Completer<MoySkladHttpResponse>();
      transport = FakeMoySkladTransport(() => completer.future);
      manager = MoySkladApiManager(
        tokenStore: tokenStore,
        apiClient: MoySkladApiClient(transport: transport),
        internet: internet.stream,
        periodicTimer: (duration, callback) {
          final timer = FakePeriodicTimer(callback);
          timers.add(timer);
          return timer;
        },
      );
      await manager.start();
      internet.add(true);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      internet.add(false);
      await Future<void>.delayed(Duration.zero);
      completer.complete(
        const MoySkladHttpResponse(statusCode: 200, body: '{}'),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(manager.currentState, ApiConnectionState.offline);
    });

    test('token save triggers an immediate check when online', () async {
      await manager.start();
      internet.add(true);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      final before = transport.calls;
      await manager.onTokenSaved();
      expect(transport.calls, before + 1);
    });

    test('token deletion immediately clears connected status', () async {
      await manager.start();
      internet.add(true);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(manager.currentState, ApiConnectionState.connected);
      manager.onTokenDeleted();
      expect(manager.currentState, ApiConnectionState.unavailable);
    });

    test(
      'creates a five minute foreground timer and cancels in background',
      () async {
        await manager.start();
        internet.add(true);
        await Future<void>.delayed(Duration.zero);
        expect(timers, isNotEmpty);
        expect(timers.last.isActive, isTrue);
        manager.setForeground(false);
        expect(timers.last.isActive, isFalse);
        final calls = transport.calls;
        now = now.add(const Duration(minutes: 6));
        manager.setForeground(true);
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        expect(transport.calls, calls + 1);
      },
    );

    test('single-flights concurrent triggers', () async {
      final completer = Completer<MoySkladHttpResponse>();
      transport = FakeMoySkladTransport(() => completer.future);
      manager = MoySkladApiManager(
        tokenStore: tokenStore,
        apiClient: MoySkladApiClient(transport: transport),
        internet: internet.stream,
        periodicTimer: (duration, callback) {
          final timer = FakePeriodicTimer(callback);
          timers.add(timer);
          return timer;
        },
      );
      await manager.start();
      internet.add(true);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      final second = manager.checkNow();
      expect(transport.calls, 1);
      completer.complete(
        const MoySkladHttpResponse(statusCode: 200, body: '{}'),
      );
      await second;
      expect(transport.calls, 2);
    });

    test('rate limit prevents checks until retry window elapses', () async {
      var now = DateTime(2026, 11, 19);
      transport = FakeMoySkladTransport(
        () async => const MoySkladHttpResponse(
          statusCode: 429,
          body: '{}',
          headers: {'retry-after': '60'},
        ),
      );
      manager = MoySkladApiManager(
        tokenStore: tokenStore,
        apiClient: MoySkladApiClient(transport: transport),
        internet: internet.stream,
        clock: () => now,
        periodicTimer: (duration, callback) {
          final timer = FakePeriodicTimer(callback);
          timers.add(timer);
          return timer;
        },
      );
      await manager.start();
      internet.add(true);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(transport.calls, 1);
      await manager.checkNow();
      expect(transport.calls, 1);
      now = now.add(const Duration(seconds: 61));
      await manager.checkNow();
      expect(transport.calls, 2);
    });
  });
}
