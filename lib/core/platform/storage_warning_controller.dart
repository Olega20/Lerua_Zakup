import 'storage_capacity_service.dart';
import 'storage_warning_policy.dart';

export 'storage_warning_policy.dart';

class StorageWarningController {
  StorageWarningController({
    required this.capacityService,
    required this.store,
    required this.onWarning,
    this.policy = const StorageWarningPolicy(),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final StorageCapacityReader capacityService;
  final StorageWarningStore store;
  final void Function() onWarning;
  final StorageWarningPolicy policy;
  final DateTime Function() _clock;
  Future<void>? _pendingCheck;

  Future<void> check() {
    final pending = _pendingCheck;
    if (pending != null) return pending;
    final operation = _performCheck();
    _pendingCheck = operation;
    return operation.whenComplete(() {
      if (identical(_pendingCheck, operation)) _pendingCheck = null;
    });
  }

  Future<void> _performCheck() async {
    final available = await capacityService.getAvailableBytes();
    final now = _clock();
    final lastWarning = await store.getLastWarningAt();
    if (!policy.shouldWarn(
      availableBytes: available,
      now: now,
      lastWarningAt: lastWarning,
    )) {
      return;
    }
    await store.setLastWarningAt(now);
    onWarning();
  }
}
