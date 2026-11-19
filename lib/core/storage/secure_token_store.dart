import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class SecureTokenStore {
  Future<String?> readToken();
  Future<void> writeToken(String token);
  Future<void> deleteToken();
}

class FlutterSecureTokenStore implements SecureTokenStore {
  FlutterSecureTokenStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _tokenKey = 'moysklad_api_token';
  final FlutterSecureStorage _storage;

  @override
  Future<String?> readToken() => _storage.read(key: _tokenKey);

  @override
  Future<void> writeToken(String token) =>
      _storage.write(key: _tokenKey, value: token);

  @override
  Future<void> deleteToken() => _storage.delete(key: _tokenKey);
}
