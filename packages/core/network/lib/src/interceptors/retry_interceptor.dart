import 'dart:async';

import 'package:dio/dio.dart';

/// Interceptor that retries requests if the `canRetry` flag in the `ExtraRequest` is set to true.
///
/// This interceptor provides an additional layer of error handling by retrying requests if they
/// fail. It uses the `retryWhen` function to determine if a request should be retried,
/// and the `handleRetry` function to execute the retry logic.
///
/// The `retryWhen` function receives the type of `DioException` and should return
/// a `FutureOr<bool>` indicating whether the request should be retried.
///
/// The `handleRetry` function receives the `DioException` and the `ErrorInterceptorHandler`
/// and allows you to implement custom retry logic, such as delaying the retry or
/// using a different request method.
class RetryInterceptor extends Interceptor {
  /// Creates a new `RetryInterceptor` with the provided retry conditions and handler.
  ///
  /// [retryWhen] A function that determines if a request should be retried based on the
  /// type of `DioException`.
  ///
  /// [handleRetry] A function that handles retrying the request.
  RetryInterceptor({this.handleRetry, this.retryWhen});

  /// A function that determines if a request should be retried based on the type of `DioException`.
  ///
  /// The function receives the type of `DioException` and should return a `FutureOr<bool>`
  /// indicating whether the request should be retried.
  final FutureOr<bool> Function(DioExceptionType type)? retryWhen;

  /// A function that handles retrying the request.
  ///
  /// The function receives the `DioException` and the `ErrorInterceptorHandler` and
  /// allows you to implement custom retry logic, such as delaying the retry or using a
  /// different request method.
  final FutureOr<void> Function(
    DioException err,
    ErrorInterceptorHandler handler,
  )?
  handleRetry;

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    /// Retrieve the `canRetry` configuration from the request options extra map.
    final canRetry = err.requestOptions.extra['canRetry'] as bool? ?? true;

    /// If the `canRetry` flag is false, do not retry the request.
    if (!canRetry) {
      super.onError(err, handler);
      return;
    }

    /// Check if the retry condition is met.
    final shouldRetry = await retryWhen?.call(err.type);

    /// If the retry condition is met, execute the retry logic.
    if (shouldRetry ?? false) {
      handleRetry?.call(err, handler);
    } else {
      /// Otherwise, handle the error as usual.
      super.onError(err, handler);
    }
  }
}
