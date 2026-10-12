import 'package:erp_kayan/core/storage/token_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// A keystore that behaves the way the real ones do when they cannot help.
///
/// On the web the keystore is a database the browser owns, and it answers
/// with nothing whenever the page may not keep anything - a private window,
/// a locked-down office machine. A phone's keystore can be locked outright.
/// Both are ordinary, and neither may cost a person the session they have
/// just been given.
class _SilentSecureStorage extends FlutterSecureStorage {
  final Map<String, String> values = <String, String>{};

  /// When set, reading raises instead of answering.
  bool refusesToAnswer = false;

  /// When set, a value is accepted and then not kept - which is what the
  /// web keystore does on a page that may not keep anything.
  bool forgetsWhatWasWritten = false;

  int reads = 0;
  int writes = 0;
  int deletes = 0;

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    reads += 1;
    if (refusesToAnswer) throw StateError('the keystore is locked');
    return values[key];
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    writes += 1;
    if (forgetsWhatWasWritten) return;
    if (value == null) {
      values.remove(key);
      return;
    }
    values[key] = value;
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    deletes += 1;
    values.remove(key);
  }
}

void main() {
  group('TokenStore', () {
    test('hands back what the keystore is holding', () async {
      final secure = _SilentSecureStorage();
      final store = TokenStore(secureStorage: secure);

      await store.saveTokens(accessToken: 'a.b.c', refreshToken: 'r.b.c');

      expect(await store.readAccessToken(), 'a.b.c');
      expect(await store.readRefreshToken(), 'r.b.c');
    });

    test('remembers the token when the keystore answers with nothing', () async {
      // What the web keystore does on a page that may not keep anything:
      // the write is accepted, the answer to every read is empty.
      final secure = _SilentSecureStorage()..forgetsWhatWasWritten = true;
      final store = TokenStore(secureStorage: secure);

      await store.saveTokens(accessToken: 'a.b.c', refreshToken: 'r.b.c');

      expect(await store.readAccessToken(), 'a.b.c');
      expect(await store.readRefreshToken(), 'r.b.c');
    });

    test('remembers the token when the keystore refuses to answer', () async {
      final secure = _SilentSecureStorage()..refusesToAnswer = true;
      final store = TokenStore(secureStorage: secure);

      await store.saveTokens(accessToken: 'a.b.c', refreshToken: 'r.b.c');

      expect(await store.readAccessToken(), 'a.b.c');
      expect(await store.readRefreshToken(), 'r.b.c');
    });

    test('forgets both copies when the session is cleared', () async {
      final secure = _SilentSecureStorage()..refusesToAnswer = true;
      final store = TokenStore(secureStorage: secure);

      await store.saveTokens(accessToken: 'a.b.c', refreshToken: 'r.b.c');
      await store.clear();

      expect(await store.readAccessToken(), isNull);
      expect(await store.readRefreshToken(), isNull);
    });

    test('has no token before anything was saved', () async {
      final secure = _SilentSecureStorage();
      final store = TokenStore(secureStorage: secure);

      expect(await store.readAccessToken(), isNull);
      expect(await store.readRefreshToken(), isNull);
    });
  });
}
