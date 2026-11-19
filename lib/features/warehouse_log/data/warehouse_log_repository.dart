import '../domain/warehouse_log_entry.dart';
import 'warehouse_log_storage.dart';

class WarehouseLogRepository {
  WarehouseLogRepository({
    required this.storage,
    this.maxEntries = 500,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final WarehouseLogStorage storage;
  final DateTime Function() _clock;
  final int maxEntries;

  Future<void> append(WarehouseLogEntry entry) =>
      storage.insert(entry, limit: maxEntries);

  Future<void> record({
    required WarehouseLogLevel level,
    required WarehouseLogEventType type,
    required String description,
    int? httpStatusCode,
    String? apiErrorCode,
  }) => append(
    WarehouseLogEntry(
      timestamp: _clock(),
      level: level,
      type: type,
      description: description,
      httpStatusCode: httpStatusCode,
      apiErrorCode: _safeApiCode(apiErrorCode),
    ),
  );

  Future<List<WarehouseLogEntry>> latest() => storage.latest(limit: maxEntries);

  Future<void> clear() => storage.clear();

  String? _safeApiCode(String? value) {
    if (value == null || value.isEmpty) return null;
    return RegExp(r'^[A-Za-z0-9_.-]{1,64}$').hasMatch(value) ? value : null;
  }
}
