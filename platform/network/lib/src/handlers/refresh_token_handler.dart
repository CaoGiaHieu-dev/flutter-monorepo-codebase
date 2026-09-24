import 'dart:async';

import 'dart:io';

import 'package:dio/dio.dart';

import '../utils/network_constants.dart';

/// Handles refreshing the token when a request fails due to an expired token.
/// This handler uses a Completer to ensure that the token is refreshed only once,
/// even when multiple requests fail concurrently. Subsequent requests will wait
/// for the initial refresh to complete.
class RefreshTokenHandler {
  /// The main Dio instance, used for retrying requests.
  final Dio dio;

  /// Renews the session. Returns the new token, `null` when the server
  /// rejected renewal (the session is over), or throws when renewal could not
  /// be attempted (the session is kept).
  final Future<String?> Function() onRefreshToken;

  /// Called once when the server rejected renewal — clear the session.
  /// Not called for a renewal that merely could not reach the server.
  final Future<void> Function() onRefreshFailed;

  /// A completer that is active during a token refresh.
  /// It completes with the new token on success, or null on failure.
  Completer<String?>? _completer;

  /// The token requests are sent with now. Optional: when given, a `401`
  /// for a request sent with an older token is replayed without refreshing.
  final String? Function()? currentToken;

  /// Creates a new instance of [RefreshTokenHandler].
  RefreshTokenHandler({
    required this.dio,
    required this.onRefreshToken,
    required this.onRefreshFailed,
    this.currentToken,
  });

  /// Handles a refresh request. This method is intended to be called from
  /// a Dio interceptor's `onError` handler.
  ///
  /// [err] The DioException that triggered the refresh.
  /// [handler] The error interceptor handler.
  Future<void> handleRefresh(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    // If a refresh is already in progress, wait for it to complete.
    if (_completer != null) {
      final String? newToken = await _completer!.future;
      if (newToken != null) {
        // The token was successfully refreshed, retry the original request.
        return _retryRequest(err, handler);
      } else {
        // The token refresh failed, reject the original request.
        return handler.reject(err);
      }
    }

    // A request sent before the last refresh finished carries the old token;
    // its 401 says nothing about the current one. Replay it with the new
    // token instead of starting another refresh — with rotating refresh
    // tokens, a redundant refresh can invalidate the session just renewed.
    final current = currentToken?.call();
    final sent = err.requestOptions.headers[HttpHeaders.authorizationHeader];
    if (current != null &&
        current.isNotEmpty &&
        sent != null &&
        sent != '${NetworkConstants.BEARER_PREFIX} $current') {
      return _retryRequest(err, handler);
    }

    // This is the first request to trigger a refresh.
    // Lock subsequent requests by creating a completer.
    final completer = _completer = Completer<String?>();

    String? newToken;
    try {
      newToken = await onRefreshToken();
    } catch (_) {
      // Renewal could not be attempted — network down, a 5xx, a cancelled
      // retry. The session may well still be valid, so it is kept: fail this
      // request and the ones waiting on it, and let the next 401 try again.
      completer.complete(null);
      _completer = null;
      return handler.reject(err);
    }

    if (newToken?.isNotEmpty ?? false) {
      completer.complete(newToken);
      try {
        // `await` keeps the refresh lock (`_completer`) held until the retry
        // finishes; releasing it earlier would let a concurrent 401 start a
        // second, redundant refresh.
        return await _retryRequest(err, handler);
      } finally {
        _completer = null;
      }
    }

    // The server rejected renewal: the session is over. A throwing callback
    // must not leave this request — or the ones queued behind it — unsettled.
    try {
      await onRefreshFailed();
    } catch (_) {
      // Safe to drop: the session is already over and this request is
      // rejected below either way — the callback's own failure changes
      // nothing, while letting it escape would leave the queue unsettled.
    }
    completer.complete(null);
    _completer = null;
    return handler.reject(err);
  }

  /// Retries the failed request using the original Dio instance.
  /// The `AuthInterceptor` is expected to inject the new token.
  Future<void> _retryRequest(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    try {
      // For FormData, we need to create a new instance for the retry.
      final requestOptions = err.requestOptions.data is FormData
          ? _recreateOptions(err.requestOptions)
          : err.requestOptions;

      final response = await dio.fetch<dynamic>(requestOptions);
      return handler.resolve(response);
    } on DioException catch (e) {
      return handler.reject(e);
    } catch (e) {
      return handler.reject(
        DioException(requestOptions: err.requestOptions, error: e),
      );
    }
  }

  /// Recreates the request options with a new FormData instance.
  /// This is necessary because FormData streams can only be used once.
  RequestOptions _recreateOptions(RequestOptions options) {
    final formData = options.data as FormData;
    final newFormData = FormData();

    newFormData.fields.addAll(formData.fields);
    for (final pair in formData.files) {
      newFormData.files.add(MapEntry(pair.key, pair.value.clone()));
    }

    return options.copyWith(data: newFormData);
  }
}
