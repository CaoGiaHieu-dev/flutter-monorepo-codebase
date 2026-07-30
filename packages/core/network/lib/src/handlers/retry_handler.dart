import 'package:dio/dio.dart';

import 'package:flutter/foundation.dart';
import '../interceptors/logging_interceptor.dart';

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
  /// [options] is the [BaseOptions] for the [Dio] client.
  RetryHandler(this.options, {this.onRetryCallback});

  /// The [BaseOptions] for the [Dio] client.
  final BaseOptions options;

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

  /// A flag that indicates whether the retry process is in progress.
  var _isRetry = false;

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
    // Remove the failed request from the queue.
    _retryQueue.removeWhere(
      (element) =>
          element.exception.requestOptions.uri.path ==
              err.requestOptions.uri.path &&
          element.exception.requestOptions.method == err.requestOptions.method,
    );

    // Add the failed request to the queue.
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
    // Set the pending flag to false.
    _isPending = false;
    // Retry all requests in the queue.
    _retryRequests();
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

  /// Retries all requests in the queue.
  ///
  /// This method will create a new [Dio] client with the same options as the original
  /// client, but with a [LoggingInterceptor] added to the interceptors list. Then, it will
  /// retry all requests in the queue using the new [Dio] client.
  void _retryRequests() {
    // If the retry process is already in progress, do nothing.
    if (_isRetry) return;
    _isRetry = true;

    // Create a new [Dio] client with the same options as the original client.
    final retryDio = Dio(options)
      // Add the logger interceptor to the new [Dio] client.
      ..interceptors.add(LoggingInterceptor(tag: 'Retry'));

    // Retry all requests in the queue.
    for (var item in _retryQueue.toList()) {
      _request(retryDio, item);
    }

    // Set the retry flag to false.
    _isRetry = false;
  }

  /// Retries a single request in the queue.
  ///
  /// This method will retry the request using the given [retryDio] client. If the
  /// retry is successful, the request will be removed from the queue. If the retry
  /// fails, the handler will handle the retry based on the error type.
  void _request(Dio retryDio, _RetryItem retryItem) async {
    // Get the request options from the retry item.
    RequestOptions options = retryItem.exception.requestOptions;

    // If the request data is a [FormData], recreate the [FormData] object.
    if (options.data is FormData) {
      options = _recreateOptions(options);
    }

    try {
      // Retry the request using the new [Dio] client.
      final value = await retryDio.fetch(options);
      // If the retry is successful, resolve the request handler.
      retryItem.errorHandler.resolve(value);
    } on DioException catch (exception) {
      // If the error is a retry able error, handle the retry.
      if (retryWhen(exception.type)) {
        handleRetry(exception, retryItem.errorHandler);
      } else {
        // If the request has already been completed, do nothing.
        if (retryItem.errorHandler.isCompleted) return;
        // Reject the request.
        retryItem.errorHandler.reject(retryItem.exception);
      }
    } catch (e) {
      // If the request has already been completed, do nothing.
      if (retryItem.errorHandler.isCompleted) return;
      // Reject the request.
      retryItem.errorHandler.reject(retryItem.exception);
    }

    // Remove the retry item from the queue.
    _retryQueue.remove(retryItem);
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
