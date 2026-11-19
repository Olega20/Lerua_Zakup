import 'package:flutter_test/flutter_test.dart';
import 'package:lerua_zakup/core/notifications/notification_service.dart';

class FakeNotificationPlatform implements NotificationPlatform {
  int channelCalls = 0;
  int permissionCalls = 0;
  bool permissionGranted = true;
  final List<String> calls = [];

  @override
  Future<void> createNotificationChannels() async {
    channelCalls++;
    calls.add('channels');
  }

  @override
  Future<bool> requestPermission() async {
    permissionCalls++;
    calls.add('permission');
    return permissionGranted;
  }
}

class FakeNotificationPermissionStore implements NotificationPermissionStore {
  bool requested = false;
  int markCalls = 0;

  @override
  Future<bool> wasPermissionRequested() async => requested;

  @override
  Future<void> markPermissionRequested() async {
    requested = true;
    markCalls++;
  }
}

void main() {
  group('NotificationService', () {
    test('creates channels and requests permission on first launch', () async {
      final platform = FakeNotificationPlatform();
      final store = FakeNotificationPermissionStore();
      final service = NotificationService(platform: platform, store: store);

      final granted = await service.initializeAndRequestPermission();

      expect(granted, isTrue);
      expect(platform.calls, ['channels', 'permission']);
      expect(store.markCalls, 1);
    });

    test('does not request permission again after the first launch', () async {
      final platform = FakeNotificationPlatform();
      final store = FakeNotificationPermissionStore()..requested = true;
      final service = NotificationService(platform: platform, store: store);

      final granted = await service.initializeAndRequestPermission();

      expect(granted, isFalse);
      expect(platform.channelCalls, 1);
      expect(platform.permissionCalls, 0);
    });

    test(
      'permission denial does not prevent notification initialization',
      () async {
        final platform = FakeNotificationPlatform()..permissionGranted = false;
        final store = FakeNotificationPermissionStore();
        final service = NotificationService(platform: platform, store: store);

        final granted = await service.initializeAndRequestPermission();

        expect(granted, isFalse);
        expect(platform.channelCalls, 1);
        expect(store.requested, isTrue);
      },
    );
  });
}