import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lerua_zakup/core/platform/storage_capacity_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('StorageCapacityService', () {
    const channel = MethodChannel('test/lerua_zakup_storage');

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('returns available bytes reported by Android', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'getAvailableStorageBytes');
            return 1024 * 1024 * 1024;
          });

      final service = StorageCapacityService(channel: channel);
      expect(await service.getAvailableBytes(), 1024 * 1024 * 1024);
    });

    test('returns null when Android cannot report storage capacity', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            throw PlatformException(code: 'unavailable');
          });

      final service = StorageCapacityService(channel: channel);
      expect(await service.getAvailableBytes(), isNull);
    });
  });
}
