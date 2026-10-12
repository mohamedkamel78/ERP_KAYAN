import 'package:dio/dio.dart';

import '../config/app_config.dart';
import '../error/failure.dart';
import '../logging/app_logger.dart';
import '../storage/token_store.dart';

/// Called when the session cannot be renewed: the refresh token is gone,
/// spent or expired, and the only honest answer is to sign the person out.
typedef SessionExpiredHandler = Future<void> Function();

/// Thin, testable wrapper around [Dio].
///
/// Responsibilities:
///  * attach the bearer token to outgoing requests
///  * renew a session that has run out, so a quarter of an hour is not a
///    reason to be thrown back to the sign-in screen
///  * translate transport errors into typed [Failure]s
///  * never log credentials, tokens or financial payloads
class ApiClient {
  ApiClient(this._config, this._tokenStore, {Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: _config.apiBaseUrl,
              connectTimeout: _config.connectTimeout,
              receiveTimeout: _config.receiveTimeout,
              contentType: Headers.jsonContentType,
              responseType: ResponseType.json,
              // Anything that is not a success is turned into a typed
              // failure below, so a 400 "not enough stock" can never be
              // mistaken for a successful response.
              validateStatus: (status) => status != null && status < 400,
            ),
          ) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _tokenStore.readAccessToken();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
            // Noted on the request, because what a refusal means depends on
            // whether a credential went out with it - and by the time the
            // answer comes back the store may hold a different one.
            options.extra[_sentWithCredential] = true;
          }
          handler.next(options);
        },
        onError: (e, handler) async {
          // A sign-in token lives for a few minutes on purpose. Nobody
          // should be asked to sign in again in the middle of the working
          // day, so a refusal is given one chance to be a token that simply
          // ran out: renew it, then send the very same request again.
          //
          // Financial Periods was where this showed itself — the first
          // screen somebody opens a while after signing in, by which time
          // the token had expired and every call behind that screen started
          // answering "Invalid or expired token".
          if (_isSessionRefusal(e) &&
              e.requestOptions.extra[_skipRenewal] != true) {
            // A refusal is only a session that ran out when a session went
            // out with the request.
            //
            // Before anybody has signed in, a screen asks for things it is
            // not entitled to and is refused - a report behind the
            // sign-in, the state of the setup, the capabilities of the
            // server. That is the ordinary shape of a program that has not
            // been signed into yet, and it is not an expired session.
            // Answering it as one clears the store and signs the person
            // out, and when that happens while a sign-in is completing it
            // takes the brand-new token with it: the person is then signed
            // in and every screen behind it answers "Missing bearer
            // token", over and over, for as long as the tab is open.
            final hadCredential =
                e.requestOptions.extra[_sentWithCredential] == true;
            final refreshable = hadCredential || await _hasRefreshToken();
            final renewed = refreshable && await _renewSession();
            if (renewed) {
              try {
                final retried = await _dio.fetch<dynamic>(
                  _authorised(e.requestOptions),
                );
                return handler.resolve(retried);
              } on DioException {
                // The renewal worked but the request itself did not; the
                // original failure is the one worth reporting.
              }
            } else if (hadCredential) {
              // There was a session and it cannot be renewed. Only then is
              // signing the person out the honest answer.
              await _tokenStore.clear();
              await onSessionExpired?.call();
            }
            // Otherwise there was nothing to renew and nobody to sign out:
            // the request simply was not allowed, and the caller is told.
          }
          handler.next(e);
        },
      ),
    );
    if (_config.enableLogging) {
      _log.info('ApiClient initialised for ${_config.environment.name}');
    }
  }

  final Dio _dio;
  final TokenStore _tokenStore;
  final AppConfig _config;
  static final _log = AppLogger.of('ApiClient');

  /// Set by whoever owns the session, so a session that cannot be renewed
  /// ends in a sign-out rather than in a screen full of errors.
  SessionExpiredHandler? onSessionExpired;

  /// A renewal already under way. Several requests fail at once when a token
  /// runs out, and only one of them may spend the refresh token — the rest
  /// wait for it, because spending it twice revokes the first renewal.
  Future<bool>? _renewing;

  static const _skipRenewal = 'skipSessionRenewal';

  /// Set on a request that went out with a sign-in token in its header.
  static const _sentWithCredential = 'sentWithCredential';

  /// Whether a refresh token is held, and so whether a refusal is worth
  /// answering with a renewal.
  Future<bool> _hasRefreshToken() async {
    final token = await _tokenStore.readRefreshToken();
    return token != null && token.isNotEmpty;
  }

  Dio get raw => _dio;

  /// A 401 that is about the session rather than about permission.
  ///
  /// 403 means "you may not": renewing the session will not change that, and
  /// trying would only add a delay before the same answer.
  bool _isSessionRefusal(DioException e) =>
      e.response?.statusCode == 401 && e.requestOptions.path != _refreshPath;

  RequestOptions _authorised(RequestOptions options) {
    // The interceptor runs again for the retry and would attach the old
    // token, so the new one is put on here and the retry is allowed to keep
    // it.
    options.extra[_skipRenewal] = true;
    return options;
  }

  /// Exchanges the refresh token for a new pair.
  ///
  /// The server rotates refresh tokens: the one sent here is spent, and only
  /// the one that comes back will work next time. That is why concurrent
  /// failures share a single renewal.
  Future<bool> _renewSession() {
    final inFlight = _renewing;
    if (inFlight != null) return inFlight;
    final renewal = _exchangeRefreshToken();
    _renewing = renewal;
    return renewal.whenComplete(() => _renewing = null);
  }

  Future<bool> _exchangeRefreshToken() async {
    try {
      final refreshToken = await _tokenStore.readRefreshToken();
      if (refreshToken == null || refreshToken.isEmpty) return false;

      final response = await _dio.post<Map<String, dynamic>>(
        _refreshPath,
        data: <String, dynamic>{'refreshToken': refreshToken},
        options: Options(extra: <String, dynamic>{_skipRenewal: true}),
      );
      final data = response.data ?? const <String, dynamic>{};
      final accessToken = data['accessToken'] as String?;
      if (accessToken == null || accessToken.isEmpty) return false;

      // Only the refresh token that came back will be good next time.
      await _tokenStore.saveTokens(
        accessToken: accessToken,
        refreshToken: data['refreshToken'] as String?,
      );
      return true;
    } on DioException {
      return false;
    }
  }

  static const _refreshPath = '/auth/refresh';

  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    return _send(() => _dio.get<dynamic>(path, queryParameters: query));
  }

  Future<Map<String, dynamic>> patch(String path, {Object? body}) async {
    return _send(() => _dio.patch<dynamic>(path, data: body));
  }

  /// Deletes a record. Used for the few things that really can be removed —
  /// a role that nobody holds, for instance.
  Future<Map<String, dynamic>> delete(String path) async {
    return _send(() => _dio.delete<dynamic>(path));
  }

  Future<Map<String, dynamic>> post(
    String path, {
    Object? body,
    String? idempotencyKey,
  }) async {
    return _send(
      () => _dio.post<dynamic>(
        path,
        data: body,
        options: Options(
          headers: idempotencyKey == null
              ? null
              : {'Idempotency-Key': idempotencyKey},
        ),
      ),
    );
  }

  /// Reads an endpoint that returns a collection.
  ///
  /// The API answers either with `{ items: [...], total: n }` for paginated
  /// resources or with a bare array for reports, and callers should not have
  /// to care which.
  Future<List<Map<String, dynamic>>> getList(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    final Response<dynamic> response;
    try {
      response = await _dio.get<dynamic>(path, queryParameters: query);
    } on DioException catch (e) {
      throw _mapDioException(e);
    }
    final data = response.data;
    final raw = data is Map && data['items'] is List
        ? data['items'] as List
        : data is List
        ? data
        : const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
  }

  /// Reads an endpoint whose body is an object with several fields.
  Future<Map<String, dynamic>> getObject(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    final Response<dynamic> response;
    try {
      response = await _dio.get<dynamic>(path, queryParameters: query);
    } on DioException catch (e) {
      throw _mapDioException(e);
    }
    final data = response.data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return <String, dynamic>{};
  }

  Future<Map<String, dynamic>> _send(
    Future<Response<dynamic>> Function() request,
  ) async {
    try {
      final response = await request();
      final data = response.data;
      if (data is Map<String, dynamic>) return data;
      if (data == null) return <String, dynamic>{};
      return <String, dynamic>{'data': data};
    } on DioException catch (e) {
      throw _mapDioException(e);
    } on Failure {
      rethrow;
    } catch (e) {
      throw ServerFailure('Unexpected client error', e);
    }
  }

  Failure _mapDioException(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
      case DioExceptionType.connectionError:
        return const NetworkFailure();
      case DioExceptionType.badCertificate:
        return const NetworkFailure('Server certificate could not be verified');
      case DioExceptionType.cancel:
        return const NetworkFailure('Request cancelled');
      case DioExceptionType.badResponse:
        final status = e.response?.statusCode ?? 0;
        final message =
            _extractMessage(e.response?.data) ??
            'Request failed with status $status';
        if (status == 401 || status == 403) {
          return AuthFailure(message);
        }
        return ApiFailure(message, statusCode: status);
      case DioExceptionType.unknown:
        return const NetworkFailure();
    }
  }

  String? _extractMessage(Object? data) {
    if (data is Map) {
      for (final key in const ['message', 'detail', 'error']) {
        final value = data[key];
        if (value is String && value.trim().isNotEmpty) return value;
      }
    }
    return null;
  }
}
