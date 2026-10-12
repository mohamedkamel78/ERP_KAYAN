import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:erp_kayan/core/config/app_config.dart';
import 'package:erp_kayan/core/error/failure.dart';
import 'package:erp_kayan/core/network/api_client.dart';
import 'package:erp_kayan/core/storage/token_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

const _config = AppConfig(
  environment: AppEnvironment.development,
  apiBaseUrl: 'http://localhost:3000/api/v1',
  connectTimeout: Duration(seconds: 5),
  receiveTimeout: Duration(seconds: 5),
);

/// A store that holds whatever it is given, and counts how often it was
/// emptied. The real one writes to a keystore; what matters here is only
/// what the client believes it holds.
class _FakeTokenStore extends TokenStore {
  _FakeTokenStore() : super(secureStorage: const FlutterSecureStorage());

  String? access;
  String? refresh;
  int emptied = 0;

  @override
  Future<String?> readAccessToken() async => access;

  @override
  Future<String?> readRefreshToken() async => refresh;

  @override
  Future<void> saveTokens({
    required String accessToken,
    String? refreshToken,
  }) async {
    access = accessToken;
    if (refreshToken != null) refresh = refreshToken;
  }

  @override
  Future<void> clear() async {
    emptied += 1;
    access = null;
    refresh = null;
  }

  @override
  Future<String?> readLocale() async => null;

  @override
  Future<void> saveLocale(String languageCode) async {}
}

ResponseBody _json(int status, Object body) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: const {
    'content-type': ['application/json'],
  },
);

/// An adapter that answers from a script, and remembers what it was asked.
class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this.answer);

  final ResponseBody Function(RequestOptions options, int attempt) answer;

  final Map<String, int> attempts = <String, int>{};
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final attempt = (attempts[options.path] ?? 0) + 1;
    attempts[options.path] = attempt;
    requests.add(options);
    return answer(options, attempt);
  }

  @override
  void close({bool force = false}) {}

  bool asked(String path) => requests.any((options) => options.path == path);
}

void main() {
  group('ApiClient - what a refusal means', () {
    test(
      'a refusal of a request that carried no credential is not an expired '
      'session',
      () async {
        // The shape of a program nobody has signed into yet: screens ask
        // for things they are not entitled to and are refused. Answering
        // that with a sign-out is what wiped the token of a sign-in that
        // was completing at the same moment.
        final store = _FakeTokenStore();
        final adapter = _ScriptedAdapter(
          (options, attempt) => _json(401, {'detail': 'Missing bearer token'}),
        );
        final client = ApiClient(
          _config,
          store,
          dio: Dio(BaseOptions(baseUrl: _config.apiBaseUrl))
            ..httpClientAdapter = adapter,
        );

        var signedOut = 0;
        client.onSessionExpired = () async {
          signedOut += 1;
        };

        await expectLater(client.get('/reports/trial-balance'), throwsA(isA<AuthFailure>()));

        expect(signedOut, 0, reason: 'nobody was signed in, so nobody was signed out');
        expect(store.emptied, 0, reason: 'there was no token to throw away');
        expect(adapter.asked('/auth/refresh'), isFalse);
      },
    );

    test('a refusal of a request that carried a credential renews and retries', () async {
      final store = _FakeTokenStore()
        ..access = 'first.token'
        ..refresh = 'first.refresh';
      final adapter = _ScriptedAdapter((options, attempt) {
        if (options.path == '/auth/refresh') {
          return _json(200, {'accessToken': 'second.token', 'refreshToken': 'second.refresh'});
        }
        return attempt == 1
            ? _json(401, {'detail': 'Invalid or expired token'})
            : _json(200, {'ok': true});
      });
      final client = ApiClient(
        _config,
        store,
        dio: Dio(BaseOptions(baseUrl: _config.apiBaseUrl))
          ..httpClientAdapter = adapter,
      );

      var signedOut = 0;
      client.onSessionExpired = () async {
          signedOut += 1;
        };

      final answer = await client.get('/accounting/chart-of-accounts');

      expect(answer, {'ok': true});
      expect(store.access, 'second.token');
      expect(signedOut, 0);
      expect(adapter.attempts['/accounting/chart-of-accounts'], 2);
    });

    test(
      'a credential that cannot be renewed ends the session, and only then',
      () async {
        // Signed in, but the refresh token is gone: there is no way back,
        // and the honest answer is to say so rather than leave every screen
        // answering the same refusal.
        final store = _FakeTokenStore()..access = 'stale.token';
        final adapter = _ScriptedAdapter(
          (options, attempt) => _json(401, {'detail': 'Invalid or expired token'}),
        );
        final client = ApiClient(
          _config,
          store,
          dio: Dio(BaseOptions(baseUrl: _config.apiBaseUrl))
            ..httpClientAdapter = adapter,
        );

        var signedOut = 0;
        client.onSessionExpired = () async {
          signedOut += 1;
        };

        await expectLater(client.get('/reports/trial-balance'), throwsA(isA<AuthFailure>()));

        expect(signedOut, 1);
        expect(store.emptied, 1);
        expect(store.access, isNull);
        expect(adapter.asked('/auth/refresh'), isFalse,
            reason: 'there was no refresh token to spend');
      },
    );

    test('the credential is put on the request when there is one', () async {
      final store = _FakeTokenStore()
        ..access = 'a.token'
        ..refresh = 'a.refresh';
      final adapter = _ScriptedAdapter(
        (options, attempt) => _json(200, {'ok': true}),
      );
      final client = ApiClient(
        _config,
        store,
        dio: Dio(BaseOptions(baseUrl: _config.apiBaseUrl))
          ..httpClientAdapter = adapter,
      );

      await client.get('/accounting/chart-of-accounts');

      expect(
        adapter.requests.single.headers['Authorization'],
        'Bearer a.token',
      );
    });
  });
}
