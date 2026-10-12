import 'package:dio/dio.dart';
import 'package:erp_kayan/core/config/app_config.dart';
import 'package:erp_kayan/core/network/api_client.dart';
import 'package:erp_kayan/core/storage/token_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// What a refusal does to the rest of the app.
///
/// These are the rules the client promises when a request comes back `401`:
/// try once to renew, tell the app when there is nothing left to renew with,
/// and never let either of those two things start a conversation with the
/// server that does not end. A recorded run of the browser check caught the
/// client calling `POST /auth/logout` 2999 times in a minute - the sign-out
/// that ends an expired session is itself refused, that refusal looked like
/// another expired session, and the rate limit that protects the server then
/// refused every download, print and report behind it.
///
/// A token store that keeps the tokens in a variable. The real one is the
/// platform keystore; what these tests turn on is which token is in hand when
/// a request is refused.
class _MemoryTokenStore extends TokenStore {
  _MemoryTokenStore({this.accessToken, this.refreshToken});

  String? accessToken;
  String? refreshToken;
  int clears = 0;

  @override
  Future<String?> readAccessToken() async => accessToken;

  @override
  Future<String?> readRefreshToken() async => refreshToken;

  @override
  Future<void> saveTokens({
    required String accessToken,
    String? refreshToken,
  }) async {
    this.accessToken = accessToken;
    if (refreshToken != null) this.refreshToken = refreshToken;
  }

  @override
  Future<void> clear() async {
    clears++;
    accessToken = null;
    refreshToken = null;
  }
}

/// Answers every request with the status the test asked for, and writes down
/// what was asked: a request that repeats is what is being looked for.
class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this.reply);

  final int Function(String path) reply;
  final List<String> asked = <String>[];

  @override
  Future<Response<dynamic>> fetch(
    RequestOptions options,
    CancelToken? cancelToken,
  ) async {
    asked.add(options.path);
    final status = reply(options.path);
    return Response<dynamic>(
      statusCode: status,
      // A success carries a token pair along with it, so the one endpoint
      // that is answered with a renewal has something to renew with.
      data: <String, dynamic>{
        'ok': status == 200,
        'accessToken': 'fresh',
        'refreshToken': 'fresh-once',
      },
      requestOptions: options,
    );
  }

  @override
  void close({bool force = false}) {}
}

ApiClient _client(_MemoryTokenStore store, _ScriptedAdapter adapter) {
  final dio = Dio(
    BaseOptions(
      baseUrl: 'http://localhost:3000/api/v1/',
      // The app's own rule: anything short of a success is an error for the
      // interceptors to look at, so a 401 here behaves as it does in the app.
      validateStatus: (status) => status != null && status < 400,
    ),
  );
  dio.httpClientAdapter = adapter;
  return ApiClient(
    AppConfig.forLocalServer('http://localhost:3000/api/v1/'),
    store,
    dio: dio,
  );
}

Future<void> _ignore(Future<dynamic> Function() action) async {
  try {
    await action();
  } catch (_) {
    // The refusal is not the subject of these tests. What is, is what the
    // client does next.
  }
}

void main() {
  test('a refusal of the sign-out request does not sign out again', () async {
    final store = _MemoryTokenStore(accessToken: 'already spent');
    final adapter = _ScriptedAdapter((path) => 401);
    final client = _client(store, adapter);
    var announced = 0;
    client.onSessionExpired = () async {
      announced++;
    };

    await _ignore(() => client.post('/auth/logout'));

    expect(announced, 0, reason: 'signing out is the end of the session');
    expect(adapter.asked.where((path) => path == '/auth/logout').length, 1);
    expect(
      adapter.asked.where((path) => path == '/auth/refresh').isEmpty,
      isTrue,
      reason: 'a token that is gone is not worth offering again',
    );
  });

  test('a session nobody can renew is announced once, not per request',
      () async {
    final store = _MemoryTokenStore(accessToken: 'expired');
    final adapter = _ScriptedAdapter((path) => 401);
    final client = _client(store, adapter);
    var announced = 0;
    client.onSessionExpired = () async {
      announced++;
    };

    await _ignore(() => client.get('/financial-periods'));
    await _ignore(() => client.get('/journal-entries'));
    await _ignore(() => client.get('/suppliers'));

    expect(announced, 1);
    expect(store.clears, greaterThan(0));
  });

  test('a request that works again re-arms the next expiry', () async {
    final store = _MemoryTokenStore(accessToken: 'expired');
    final adapter = _ScriptedAdapter(
      (path) => path == '/auth/me' ? 200 : 401,
    );
    final client = _client(store, adapter);
    var announced = 0;
    client.onSessionExpired = () async {
      announced++;
    };

    await _ignore(() => client.get('/financial-periods'));
    await _ignore(() => client.get('/auth/me'));
    await _ignore(() => client.get('/journal-entries'));

    expect(announced, 2);
  });

  test('a refusal that can be renewed sends the request once more', () async {
    final store = _MemoryTokenStore(
      accessToken: 'expired',
      refreshToken: 'still good',
    );
    var suppliersAsked = 0;
    final adapter = _ScriptedAdapter((path) {
      if (path == '/auth/refresh') return 200;
      if (path == '/suppliers') {
        suppliersAsked++;
        return suppliersAsked == 1 ? 401 : 200;
      }
      return 200;
    });
    final client = _client(store, adapter);
    var announced = 0;
    client.onSessionExpired = () async {
      announced++;
    };

    await _ignore(() => client.get('/suppliers'));

    expect(announced, 0, reason: 'the renewal held, so nothing expired');
    expect(adapter.asked.where((path) => path == '/auth/refresh').length, 1);
    expect(suppliersAsked, 2);
    expect(store.accessToken, 'fresh');
  });
}
