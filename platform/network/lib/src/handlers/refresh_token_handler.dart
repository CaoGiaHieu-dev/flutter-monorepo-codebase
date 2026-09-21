import 'dart:async';

import 'package:dio/dio.dart';

/// Handles refreshing the token when a request fails due to an expired token.
/// This handler uses a Completer to ensure that the token is refreshed only once,
/// even when multiple requests fail concurrently. Subsequent requests will wait
/// for the initial refresh to complete.
class RefreshTokenHandler {
  /// The main Dio instance, used for retrying requests.
  final Dio dio;

  /// Callback to refresh the token, returning the new token or null if failed.
  final Future<String?> Function() onRefreshToken;

  /// Callback to handle token refresh failure (e.g. log out or clear storage).
  final Future<void> Function() onRefreshFailed;

  /// A completer that is active during a token refresh.
  /// It completes with the new token on success, or null on failure.
  Completer<String?>? _completer;

  /// Creates a new instance of [RefreshTokenHandler].
  RefreshTokenHandler({
    required this.dio,
    required this.onRefreshToken,
    required this.onRefreshFailed,
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

    // This is the first request to trigger a refresh.
    // Lock subsequent requests by creating a completer.
    _completer = Completer<String?>();

    try {
      // Call the refresh token callback.
      final String? newToken = await onRefreshToken();

      if (newToken?.isNotEmpty ?? false) {
        // Complete the completer with the new token to unblock waiting requests.
        _completer!.complete(newToken);
        // Retry the current request that initiated the refresh.
        // `await` keeps the refresh lock (`_completer`) held until the retry
        // finishes; without it the `finally` below clears the lock early and a
        // concurrent 401 would start a second, redundant refresh.
        return await _retryRequest(err, handler);
      } else {
        // Clear local token/session by calling failure callback.
        await onRefreshFailed();
        // Complete the completer with null to notify waiting requests of the failure.
        _completer!.complete(null);
        // Reject the current request.
        return handler.reject(err);
      }
    } catch (e) {
      // In case of an unexpected error during the refresh process.
      _completer?.complete(null);
      await onRefreshFailed();
      return handler.reject(err);
    } finally {
      // Reset the completer to allow for future refreshes.
      _completer = null;
    }
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

      final response = await dio.fetch(requestOptions);
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
