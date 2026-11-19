import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract interface class NotificationPlatform {
  Future<void> createNotificationChannels();
  Future<bool> requestPermission();
}

abstract interface class NotificationPermissionStore {
  Future<bool> wasPermissionRequested();
  Future<void> markPermissionRequested();
}

class MethodChannelNotificationPlatform implements NotificationPlatform {
  static const _channel = MethodChannel('lerua_zakup/notifications');

  @override
  Future<void> createNotificationChannels() async {
    await _channel.invokeMethod<void>('createChannels');
  }

  @override
  Future<bool> requestPermission() async =>
      await _channel.invokeMethod<bool>('requestPermission') ?? false;
}

class SharedPreferencesNotificationPermissionStore
    implements NotificationPermissionStore {
  static const _key = 'notification_permission_requested';

  @override
  Future<bool> wasPermissionRequested() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(_key) ?? false;
  }

  @override
  Future<void> markPermissionRequested() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_key, true);
  }
}

class NotificationService {
  NotificationService({required this.platform, required this.store});

  final NotificationPlatform platform;
  final NotificationPermissionStore store;

  Future<bool> initializeAndRequestPermission() async {
    await platform.createNotificationChannels();
    if (await store.wasPermissionRequested()) return false;
    // Mark before the system prompt: denial is respected and never nagged again.
    await store.markPermissionRequested();
    return platform.requestPermission();
  }
}