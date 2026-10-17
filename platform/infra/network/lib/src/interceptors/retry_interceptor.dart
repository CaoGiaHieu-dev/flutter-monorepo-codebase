import 'dart:async';

import 'package:dio/dio.dart';
import 'package:dynamic_logger/dynamic_logger.dart';

import '../utils/network_constants.dart';

/// Interceptor that retries requests if the request's `NetworkConstants.EXTRA_CAN_RETRY` extra is true.
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

  /// Hands a retryable failure to [handleRetry]; passes everything else on.
  ///
  /// Dio's `onError` is synchronous, so the decision runs in [_decide] and
  /// every path ends the handler: passed on, or owned by [handleRetry]. An
  /// exception thrown by [retryWhen] or [handleRetry] is logged and the
  /// original error passed on — before, `void … async` let it escape as an
  /// uncaught zone error and left the request waiting forever.
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    unawaited(_decide(err, handler));
  }

  Future<void> _decide(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    try {
      final canRetry =
          err.requestOptions.extra[NetworkConstants.EXTRA_CAN_RETRY] as bool? ??
          true;
      final retry = handleRetry;
      final shouldRetry =
          canRetry &&
          retry != null &&
          (await retryWhen?.call(err.type) ?? false);
      if (!shouldRetry) {
        handler.next(err);
        return;
      }
      await retry(err, handler);
    } catch (error, stackTrace) {
      DynamicLogger.log(
        'Retry decision failed for ${err.requestOptions.uri}: $error',
        tag: NetworkConstants.CLIENT_LOG_TAG,
        level: LogLevel.ERROR,
        stackTrace: stackTrace,
      );
      if (!handler.isCompleted) handler.next(err);
    }
  }
}
