import 'package:flutter_test/flutter_test.dart';
import 'package:lerua_zakup/core/storage/secure_token_store.dart';

class FakeSecureTokenStore implements SecureTokenStore {
  String? token;
  bool shouldThrow = false;

  @override
  Future<String?> readToken() async {
    if (shouldThrow) throw StateError('secure read failed');
    return token;
  }

  @override
  Future<void> writeToken(String value) async {
    if (shouldThrow) throw StateError('secure write failed');
    token = value;
  }

  @override
  Future<void> deleteToken() async {
    if (shouldThrow) throw StateError('secure delete failed');
    token = null;
  }
}

void main() {
  test('reads a stored token', () async {
    final store = FakeSecureTokenStore()..token = 'secret-value';
    expect(await store.readToken(), 'secret-value');
  });

  test('writes and deletes a token', () async {
    final store = FakeSecureTokenStore();
    await store.writeToken('secret-value');
    expect(store.token, 'secret-value');
    await store.deleteToken();
    expect(store.token, isNull);
  });

  test('propagates secure storage errors', () async {
    final store = FakeSecureTokenStore()..shouldThrow = true;
    await expectLater(store.readToken(), throwsStateError);
    await expectLater(store.writeToken('secret-value'), throwsStateError);
    await expectLater(store.deleteToken(), throwsStateError);
  });
}
