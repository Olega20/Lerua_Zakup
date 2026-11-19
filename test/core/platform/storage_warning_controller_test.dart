import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lerua_zakup/core/platform/storage_capacity_service.dart';
import 'package:lerua_zakup/core/platform/storage_warning_controller.dart';

class FakeStorageCapacityService implements StorageCapacityReader {
  FakeStorageCapacityService(this.availableBytes);

  int? availableBytes;
  int calls = 0;

  @override
  Future<int?> getAvailableBytes() async {
    calls++;
    return availableBytes;
  }
}

class FakeStorageWarningStore implements StorageWarningStore {
  DateTime? lastWarningAt;
  int writes = 0;

  @override
  Future<DateTime?> getLastWarningAt() async => lastWarningAt;

  @override
  Future<void> setLastWarningAt(DateTime value) async {
    writes++;
    lastWarningAt = value;
  }
}

void main() {
  group('StorageWarningController', () {
    final now = DateTime(2026, 11, 19, 12);
    const threshold = 500 * 1024 * 1024;

    test('shows a warning and persists its timestamp when storage is low', () async {
      final service = FakeStorageCapacityService(threshold - 1);
      final store = FakeStorageWarningStore();
      var warnings = 0;
      final controller = StorageWarningController(
        capacityService: service,
        store: store,
        onWarning: () => warnings++,
        policy: const StorageWarningPolicy(thresholdBytes: threshold),
        clock: () => now,
      );

      await controller.check();

      expect(warnings, 1);
      expect(store.lastWarningAt, now);
      expect(store.writes, 1);
    });

    test('does not repeat warning within the cooldown', () async {
      final service = FakeStorageCapacityService(threshold - 1);
      final store = FakeStorageWarningStore()
        ..lastWarningAt = now.subtract(const Duration(hours: 1));
      var warnings = 0;
      final controller = StorageWarningController(
        capacityService: service,
        store: store,
        onWarning: () => warnings++,
        policy: const StorageWarningPolicy(thresholdBytes: threshold),
        clock: () => now,
      );

      await controller.check();

      expect(warnings, 0);
      expect(store.writes, 0);
    });

    test('does not warn if capacity cannot be read', () async {
      final service = FakeStorageCapacityService(null);
      final store = FakeStorageWarningStore();
      var warnings = 0;
      final controller = StorageWarningController(
        capacityService: service,
        store: store,
        onWarning: () => warnings++,
        policy: const StorageWarningPolicy(thresholdBytes: threshold),
        clock: () => now,
      );

      await controller.check();

      expect(warnings, 0);
      expect(store.writes, 0);
    });

    test('does not run concurrent storage checks', () async {
      final service = _DelayedStorageCapacityService(threshold - 1);
      final store = FakeStorageWarningStore();
      var warnings = 0;
      final controller = StorageWarningController(
        capacityService: service,
        store: store,
        onWarning: () => warnings++,
        policy: const StorageWarningPolicy(thresholdBytes: threshold),
        clock: () => now,
      );

      final first = controller.check();
      final second = controller.check();
      service.complete();
      await Future.wait([first, second]);

      expect(service.calls, 1);
      expect(warnings, 1);
    });
  });
}

class _DelayedStorageCapacityService implements StorageCapacityReader {
  _DelayedStorageCapacityService(this.value);

  final int? value;
  final completer = Completer<int?>();
  int calls = 0;

  @override
  Future<int?> getAvailableBytes() {
    calls++;
    return completer.future;
  }

  void complete() => completer.complete(value);
}
