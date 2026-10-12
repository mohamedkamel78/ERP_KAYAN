import 'package:erp_kayan/core/error/failure.dart';
import 'package:erp_kayan/core/storage/token_store.dart';
import 'package:erp_kayan/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:erp_kayan/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';

/// Restoring a session is the quiet job of picking up where the last window
/// left off. The rule these tests hold is narrow and important: only the
/// server, saying the credential itself is no good, may throw a saved token
/// away.
///
/// That rule matters twice over. On the web the token store is shared by every
/// tab of the app, so a tab that could not reach the server used to sign the
/// person out of all of them - and the screen they opened next answered
/// "Invalid or expired token", which is the report this repository exists to
/// make impossible.
class _FakeStore extends TokenStore {
  _FakeStore({this.accessToken, this.refreshToken});

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

class _FakeRemote implements AuthRemoteDataSource {
  _FakeRemote({this.reply});

  /// What `currentUser()` does: return a body, or throw this failure.
  final Object? reply;

  /// How many times the repository went to the server. A person who never
  /// signed in should not cause a request at all.
  int currentUserCalls = 0;

  @override
  Future<Map<String, dynamic>> currentUser() async {
    currentUserCalls++;
    final answer = reply;
    if (answer is Failure) throw answer;
    if (answer != null) throw answer;
    return <String, dynamic>{
      'id': 'u1',
      'username': 'admin',
      'fullName': 'مدير النظام',
      'isSuperAdmin': true,
      'branchId': null,
      'permissions': <String>[],
    };
  }

  @override
  Future<Map<String, dynamic>> login({
    required String username,
    required String password,
  }) async => throw UnimplementedError();

  @override
  Future<void> logout() async {}
}

void main() {
  test('a session that the server refuses is ended', () async {
    final store = _FakeStore(accessToken: 'spent', refreshToken: 'old');
    final repository = AuthRepositoryImpl(
      _FakeRemote(reply: const AuthFailure('Invalid or expired token')),
      store,
    );

    final result = await repository.restoreSession();

    expect(result.isFailure, isTrue);
    expect(store.clears, 1, reason: 'a refused credential is not worth keeping');
    expect(store.accessToken, isNull);
  });

  test('a server that cannot be reached keeps the session', () async {
    final store = _FakeStore(accessToken: 'good', refreshToken: 'renewable');
    final repository = AuthRepositoryImpl(
      _FakeRemote(reply: const NetworkFailure()),
      store,
    );

    final result = await repository.restoreSession();

    expect(result.isFailure, isTrue);
    expect(store.clears, 0);
    expect(store.accessToken, 'good');
    expect(store.refreshToken, 'renewable');
  });

  test('a server error of its own keeps the session too', () async {
    final store = _FakeStore(accessToken: 'good');
    final repository = AuthRepositoryImpl(
      _FakeRemote(reply: const ServerFailure('boom')),
      store,
    );

    await repository.restoreSession();

    expect(store.clears, 0);
    expect(store.accessToken, 'good');
  });

  test('an app that never signed in has nothing to restore', () async {
    final store = _FakeStore();
    final remote = _FakeRemote();
    final repository = AuthRepositoryImpl(remote, store);
    // No token stored: the repository must not go asking the server, and it
    // must not report a failure - "nobody is signed in" is a normal state.
    final result = await repository.restoreSession();
    expect(result.valueOrNull, isNull);
    expect(remote.currentUserCalls, 0);
  });

  test('a working token comes back with the person it belongs to', () async {
    final store = _FakeStore(accessToken: 'good');
    final repository = AuthRepositoryImpl(_FakeRemote(), store);

    final result = await repository.restoreSession();

    expect(result.valueOrNull?.username, 'admin');
    expect(store.clears, 0);
  });
}
