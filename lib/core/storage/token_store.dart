import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../logging/app_logger.dart';

/// Persists authentication tokens in the platform keystore and non-sensitive
/// preferences (such as the selected locale) in shared preferences.
///
/// Tokens are never written to shared preferences or to logs.
class TokenStore {
  TokenStore({FlutterSecureStorage? secureStorage})
    : _secure = secureStorage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _secure;

  static final _log = AppLogger.of('TokenStore');

  /// What was handed to [saveTokens] during this run of the program.
  ///
  /// The keystore is somewhere else: behind a platform channel on a phone,
  /// and in a database the browser owns on the web. Either can be asked for
  /// a value and answer with nothing - a private window, a browser told not
  /// to keep anything, an office machine locked down - and on the web that
  /// is an everyday answer rather than a broken machine.
  ///
  /// "The keystore said nothing" is not the same as "there is no token":
  /// one may have been handed over seconds ago. Forgetting it leaves a
  /// person who has plainly signed in looking at a screen full of
  /// refusals, so what was saved is remembered here as well, and a read
  /// that comes back empty falls back to it. Nothing is written to disk
  /// that was not already being kept, and [clear] forgets both.
  String? _memoryAccessToken;
  String? _memoryRefreshToken;

  static const _kAccessToken = 'auth.access_token';
  static const _kRefreshToken = 'auth.refresh_token';
  static const _kLocale = 'app.locale';

  Future<String?> readAccessToken() =>
      _read(_kAccessToken, () => _memoryAccessToken);

  Future<String?> readRefreshToken() =>
      _read(_kRefreshToken, () => _memoryRefreshToken);

  Future<void> saveTokens({
    required String accessToken,
    String? refreshToken,
  }) async {
    // Remembered before the write is attempted, so a keystore that refuses
    // the value does not take the session with it.
    _memoryAccessToken = accessToken;
    if (refreshToken != null) _memoryRefreshToken = refreshToken;

    await _secure.write(key: _kAccessToken, value: accessToken);
    if (refreshToken != null) {
      await _secure.write(key: _kRefreshToken, value: refreshToken);
    }
  }

  Future<void> clear() async {
    _memoryAccessToken = null;
    _memoryRefreshToken = null;
    await _secure.delete(key: _kAccessToken);
    await _secure.delete(key: _kRefreshToken);
  }

  Future<String?> readLocale() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kLocale);
  }

  Future<void> saveLocale(String languageCode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLocale, languageCode);
  }

  /// The value in the keystore, or what was saved during this run when the
  /// keystore has nothing to say.
  Future<String?> _read(String key, String? Function() remembered) async {
    try {
      final value = await _secure.read(key: key);
      if (value != null && value.isNotEmpty) {
        _remember(key, value);
        return value;
      }
    } catch (error) {
      // A keystore that cannot be opened must not crash the program, and
      // the reason is worth a line in the log - without the value, which
      // is the one thing that must never be written down.
      _log.warning('The secure store could not be read ($key): $error');
    }
    return remembered();
  }

  void _remember(String key, String value) {
    if (key == _kAccessToken) _memoryAccessToken = value;
    if (key == _kRefreshToken) _memoryRefreshToken = value;
  }
}
