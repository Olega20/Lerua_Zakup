import 'dart:io';

import 'package:flutter/foundation.dart';

/// Last-resort diagnostics used when the primary SQLite journal is unavailable.
/// Only component and exception type are persisted; raw exception text may
/// contain private paths, request data or credentials.
class EmergencyDiagnosticSink {
  const EmergencyDiagnosticSink._();
  static Future<void> record(String component, Object error) async {
    final line =
        '${DateTime.now().toIso8601String()} | '
        '${component.replaceAll(RegExp(r'[^A-Za-z0-9 _.-]'), '')} | '
        '${error.runtimeType}\n';
    try {
      final file = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}lerua_zakup_emergency.log',
      );
      await file.writeAsString(line, mode: FileMode.append, flush: true);
    } catch (_) {
      debugPrint(
        'Lerua Zakup emergency diagnostic sink unavailable: ${error.runtimeType}',
      );
    }
  }
}
