import 'package:dio/dio.dart';

import 'package:flutter/foundation.dart';

import '../utils/network_constants.dart';

/// A class that handles retrying requests when there is an error.
///
/// This class will retry requests when the error is a [DioExceptionType.receiveTimeout],
/// [DioExceptionType.sendTimeout], [DioExceptionType.connectionError], or
/// [DioExceptionType.connectionTimeout].
///
/// The retry handler will show a dialog to the user asking them if they want to retry the
/// request. If the user clicks "retry", the handler will retry all requests in the queue.
/// If the user clicks "cancel", the handler will reject all requests in the queue.
class RetryHandler {
  /// Constructs a [RetryHandler] object.
  ///
  /// [dio] is the client whose requests are retried. Replays go back through
  /// it, so the auth and refresh interceptors run again: the bearer token is
  /// re-read and a 401 on the replay is refreshed like any other.
  RetryHandler(this.dio, {this.onRetryCallback});

  /// The client whose failed requests this handler replays.
  final Dio dio;

  /// Callback to show the retry dialog.
  final void Function({
    required VoidCallback onRetry,
    required VoidCallback onCancel,
  })?
  onRetryCallback;

  /// A queue of retry items.
  ///
  /// Each item in the queue represents a request that needs to be retried.
  final _retryQueue = <_RetryItem>{};

  /// A flag that indicates whether the retry dialog is being shown.
  var _isPending = false;

  /// Checks if the retry is needed based on the [DioExceptionType].
  ///
  /// Returns `true` if the error is a [DioExceptionType.receiveTimeout],
  /// [DioExceptionType.sendTimeout], [DioExceptionType.connectionError], or
  /// [DioExceptionType.connectionTimeout], and `false` otherwise.
  bool retryWhen(DioExceptionType type) {
    return type == DioExceptionType.receiveTimeout ||
        type == DioExceptionType.sendTimeout ||
        type == DioExceptionType.connectionError ||
        type == DioExceptionType.connectionTimeout;
  }

  /// Handles the retry process when an error occurs.
  ///
  /// This method will remove the failed request from the queue, add the failed request
  /// to the queue, and show a dialog to the user asking them if they want to retry the
  /// request. If the user clicks "retry", the handler will retry all requests in the queue.
  /// If the user clicks "cancel", the handler will reject all requests in the queue.
  void handleRetry(DioException err, ErrorInterceptorHandler handler) {
    // One entry per caller. Matching on anything coarser (path + method)
    // silently dropped a second caller's request — `/items?page=1` and
    // `?page=2` share a path — leaving its Future pending forever.
    _retryQueue.removeWhere(
      (element) => identical(element.errorHandler, handler),
    );
    _retryQueue.add(_RetryItem(exception: err, errorHandler: handler));

    // If the dialog is already being shown, do nothing.
    if (_isPending) return;
    _isPending = true;

    // if onRetryCallback is not provided, retry all requests is cancel.
    if (onRetryCallback == null) {
      _cancelAllRequests();
      return;
    }
    onRetryCallback?.call(
      onRetry: _retryAllRequests,
      onCancel: _cancelAllRequests,
    );
  }

  /// Retries all requests in the queue.
  ///
  /// This method will retry all requests in the queue using the same [Dio] client as the original
  /// client.
  void _retryAllRequests() {
    _isPending = false;
    // Take the items out of the queue before sending them. Left in place,
    // a request that times out again while others are still in flight would
    // open a new dialog over a queue that still held the in-flight ones — and
    // a second retry would send them twice, a cancel would reject them while
    // their replay was about to resolve.
    final items = _retryQueue.toList();
    _retryQueue.clear();
    for (final item in items) {
      _request(item);
    }
  }

  /// Cancels all requests in the queue.
  ///
  /// This method will reject all requests in the queue.
  void _cancelAllRequests() {
    // Reject all requests in the queue.
    for (var item in _retryQueue) {
      // If the request has already been completed, skip it.
      if (item.errorHandler.isCompleted) continue;
      // Reject the request.
      item.errorHandler.reject(item.exception);
    }
    // Clear the queue.
    _retryQueue.clear();
    _isPending = false;
  }

  /// Replays one request through [dio].
  ///
  /// The replay is marked `canRetry: false` so the retry interceptor lets its
  /// failure through to here: a retryable failure re-queues the same caller,
  /// anything else is reported as *that* failure — not the original timeout.
  Future<void> _request(_RetryItem retryItem) async {
    final handler = retryItem.errorHandler;
    var options = retryItem.exception.requestOptions;
    if (options.data is FormData) {
      options = _recreateOptions(options);
    }
    options = options.copyWith(
      extra: {...options.extra, NetworkConstants.EXTRA_CAN_RETRY: false},
    );

    try {
      final value = await dio.fetch<dynamic>(options);
      if (!handler.isCompleted) handler.resolve(value);
    } on DioException catch (exception) {
      if (handler.isCompleted) return;
      if (retryWhen(exception.type)) {
        handleRetry(exception, handler);
      } else {
        handler.reject(exception);
      }
    } catch (e) {
      if (handler.isCompleted) return;
      handler.reject(
        DioException(requestOptions: options, error: e),
      );
    }
  }

  /// Recreates the [FormData] object.
  ///
  /// This method will recreate the [FormData] object with the same fields and files as the
  /// original [FormData] object. This is necessary because the [FormData] object cannot be
  /// cloned directly.
  RequestOptions _recreateOptions(RequestOptions options) {
    // Check if the request data is a [FormData].
    if (options.data is! FormData) {
      throw ArgumentError(
        'requestOptions.data is not FormData',
        'requestOptions',
      );
    }
    // Cast the request data to a [FormData].
    final formData = options.data as FormData;
    // Create a new [FormData] object.
    final newFormData = FormData();
    // Add all fields from the original [FormData] object to the new [FormData] object.
    newFormData.fields.addAll(formData.fields);
    // Add all files from the original [FormData] object to the new [FormData] object.
    for (final pair in formData.files) {
      final file = pair.value;
      newFormData.files.add(MapEntry(pair.key, file.clone()));
    }
    // Return the new [RequestOptions] object with the new [FormData] object.
    return options.copyWith(data: newFormData);
  }
}

/// A class that represents a retry item.
///
/// Each retry item contains the [DioException] that occurred and the
/// [ErrorInterceptorHandler] that was used to handle the request.
class _RetryItem {
  /// The [DioException] that occurred.
  final DioException exception;

  /// The [ErrorInterceptorHandler] that was used to handle the request.
  final ErrorInterceptorHandler errorHandler;

  /// Constructs a [_RetryItem] object.
  ///
  /// [exception] is the [DioException] that occurred.
  /// [errorHandler] is the [ErrorInterceptorHandler] that was used to handle the request.
  _RetryItem({required this.exception, required this.errorHandler});
}
