import 'package:flutter_test/flutter_test.dart';
import 'package:lerua_zakup/core/platform/storage_warning_policy.dart';

void main() {
  group('StorageWarningPolicy', () {
    const threshold = 500 * 1024 * 1024;
    const policy = StorageWarningPolicy(thresholdBytes: threshold);
    final now = DateTime(2026, 11, 19, 12);

    test('warns below the threshold', () {
      expect(
        policy.shouldWarn(
          availableBytes: threshold - 1,
          now: now,
          lastWarningAt: null,
        ),
        isTrue,
      );
    });

    test('does not warn at the threshold', () {
      expect(
        policy.shouldWarn(
          availableBytes: threshold,
          now: now,
          lastWarningAt: null,
        ),
        isFalse,
      );
    });

    test('does not warn above the threshold', () {
      expect(
        policy.shouldWarn(
          availableBytes: threshold + 1,
          now: now,
          lastWarningAt: null,
        ),
        isFalse,
      );
    });

    test('does not warn when capacity is unavailable', () {
      expect(
        policy.shouldWarn(
          availableBytes: null,
          now: now,
          lastWarningAt: null,
        ),
        isFalse,
      );
    });

    test('rate limits repeated warnings to once per 24 hours', () {
      expect(
        policy.shouldWarn(
          availableBytes: threshold - 1,
          now: now,
          lastWarningAt: now.subtract(const Duration(hours: 23, minutes: 59)),
        ),
        isFalse,
      );
      expect(
        policy.shouldWarn(
          availableBytes: threshold - 1,
          now: now,
          lastWarningAt: now.subtract(const Duration(hours: 24)),
        ),
        isTrue,
      );
    });

    test('does not warn when device clock is earlier than last warning', () {
      expect(
        policy.shouldWarn(
          availableBytes: threshold - 1,
          now: now,
          lastWarningAt: now.add(const Duration(minutes: 1)),
        ),
        isFalse,
      );
    });
  });
}
