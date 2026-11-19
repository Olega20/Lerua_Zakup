class StorageWarningPolicy {
  const StorageWarningPolicy({
    this.thresholdBytes = 500 * 1024 * 1024,
    this.cooldown = const Duration(hours: 24),
  });

  final int thresholdBytes;
  final Duration cooldown;

  bool shouldWarn({
    required int? availableBytes,
    required DateTime now,
    required DateTime? lastWarningAt,
  }) {
    if (availableBytes == null || availableBytes >= thresholdBytes) {
      return false;
    }
    if (lastWarningAt == null) return true;
    if (now.isBefore(lastWarningAt)) return false;
    return now.difference(lastWarningAt) >= cooldown;
  }
}
