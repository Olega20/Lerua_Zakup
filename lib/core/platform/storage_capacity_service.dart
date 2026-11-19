import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract interface class StorageCapacityReader {
  Future<int?> getAvailableBytes();
}

class StorageCapacityService implements StorageCapacityReader {
  StorageCapacityService({
    this.channel = const MethodChannel('lerua_zakup/platform'),
  });

  final MethodChannel channel;

  @override
  Future<int?> getAvailableBytes() async {
    try {
      return await channel.invokeMethod<int>('getAvailableStorageBytes');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}

abstract interface class StorageWarningStore {
  Future<DateTime?> getLastWarningAt();
  Future<void> setLastWarningAt(DateTime value);
}

class SharedPreferencesStorageWarningStore implements StorageWarningStore {
  static const _key = 'low_storage_warning_last_shown';

  @override
  Future<DateTime?> getLastWarningAt() async {
    final preferences = await SharedPreferences.getInstance();
    final milliseconds = preferences.getInt(_key);
    if (milliseconds == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(milliseconds);
  }

  @override
  Future<void> setLastWarningAt(DateTime value) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(_key, value.millisecondsSinceEpoch);
  }
}
