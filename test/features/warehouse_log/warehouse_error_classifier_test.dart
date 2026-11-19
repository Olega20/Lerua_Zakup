import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lerua_zakup/features/warehouse_log/domain/warehouse_error_classifier.dart';
import 'package:lerua_zakup/features/warehouse_log/domain/warehouse_log_entry.dart';

void main() {
  const classifier = WarehouseErrorClassifier();

  test('translates timeout into an actionable safe diagnostic', () {
    final result = classifier.describe(TimeoutException('secret token=abc'));
    expect(result.type, WarehouseLogEventType.timeout);
    expect(result.code, 'NETWORK_TIMEOUT');
    expect(result.message, contains('ожидания'));
    expect(result.recommendedAction, contains('интернет'));
    expect(result.technicalDetails, isNot(contains('abc')));
  });

  test('classifies local database failures separately', () {
    final result = classifier.describe(Exception('database failure'));
    // Unknown exception text is never copied to the diagnostic.
    expect(result.code, 'UNEXPECTED_ERROR');
    expect(result.technicalDetails, contains('Exception'));
    expect(result.technicalDetails, isNot(contains('database failure')));
  });

  test('does not expose platform exception messages', () {
    final result = classifier.describe(
      PlatformException(code: 'storage_error', message: 'token=secret'),
    );
    expect(result.code, 'PLATFORM_SERVICE_ERROR');
    expect(result.technicalDetails, contains('storage_error'));
    expect(result.technicalDetails, isNot(contains('secret')));
  });

  test('redacts bearer and token assignments from safe journal text', () {
    final text = sanitizeDiagnosticText(
      'Authorization: Bearer abc.def token=secret access_token:xyz',
    );
    expect(text, isNot(contains('abc.def')));
    expect(text, isNot(contains('secret')));
    expect(text, isNot(contains('xyz')));
  });
}
