import 'dart:io';

import 'package:dio/dio.dart';

import '../utils/error_codes.dart';
import 'exceptions.dart';
import 'failures.dart';

/// Global error handler for transforming exceptions to failures
///
/// This utility class provides centralized error handling and transformation
/// logic for converting platform-specific exceptions into domain failures.
/// It ensures consistent error handling across all layers of the application.
///
/// The error handler follows these transformation rules:
/// - Network-related exceptions → NetworkFailure
/// - HTTP error responses → ServerFailure
/// - Authentication errors → AuthFailure
/// - Storage errors → StorageFailure
/// - Validation errors → ValidationFailure
/// - Parsing errors → ParseFailure
/// - Cache errors → CacheFailure
/// - Service errors → ServiceFailure
/// - Unknown errors → ServerFailure with generic message
///
/// Example usage:
/// ```dart
/// try {
///   final result = await apiCall();
///   return Success(result);
/// } catch (e) {
///   return Failure(ErrorHandler.handleError(e));
/// }
/// ```
/// `kDebugMode` without importing Flutter: the VM defines `dart.vm.product`
/// in a release build and leaves it false otherwise, which is exactly what
/// `kDebugMode` reports.
const bool _isDebug = !bool.fromEnvironment('dart.vm.product');

class ErrorHandler {
  /// Private constructor to prevent instantiation
  ErrorHandler._();

  /// Transforms any exception into an appropriate [AppFailure]
  ///
  /// This method analyzes the type and content of the exception and
  /// returns the most appropriate failure type. It handles both
  /// custom application exceptions and platform-specific exceptions.
  ///
  /// Parameters:
  /// - [error]: The exception to transform
  /// - [stackTrace]: Optional stack trace for debugging
  ///
  /// Returns an [AppFailure] that represents the error in domain terms
  ///
  /// **Never throws.** Every repository funnels its `catch` through here, so
  /// an exception escaping this method would escape `IBaseRepository.execute`
  /// too — and a caller awaiting a `Result` (a provider in its loading state)
  /// would never get one. Anything that goes wrong while classifying [error]
  /// therefore degrades to the generic unknown-error failure.
  static AppFailure handleError(dynamic error, [StackTrace? stackTrace]) {
    try {
      return _classify(error);
    } catch (_) {
      return const ServerFailure(
        message: _unknownMessage,
        code: ErrorCodes.UNKNOWN,
      );
    }
  }

  /// Message of the generic failure shown in release builds.
  static const String _unknownMessage = 'Unknown error occurred';

  /// The classification behind [handleError]; may throw on a hostile
  /// [error] (a `toString` that throws, say), which [handleError] absorbs.
  static AppFailure _classify(dynamic error) {
    // Handle custom application exceptions
    if (error is AppException) {
      return _handleAppException(error);
    }

    // Handle Dio HTTP exceptions
    if (error is DioException) {
      return _handleDioException(error);
    }

    // Handle platform-specific exceptions
    if (error is SocketException) {
      return const NetworkFailure(
        message: 'No internet connection',
        code: 1001,
      );
    }

    if (error is HttpException) {
      return NetworkFailure(
        message: 'Network error: ${error.message}',
        code: 1002,
      );
    }

    if (error is FormatException) {
      return ParseFailure(
        message: 'Invalid data format: ${error.message}',
        code: 4001,
      );
    }

    // Handle generic exceptions
    return ServerFailure(
      message: _isDebug ? error.toString() : _unknownMessage,
      code: ErrorCodes.UNKNOWN,
    );
  }

  /// Transforms custom application exceptions to failures
  static AppFailure _handleAppException(AppException exception) {
    return exception.when(
      network: (message, code) => NetworkFailure(message: message, code: code),
      server: (message, code) => ServerFailure(message: message, code: code),
      auth: (message, code) => AuthFailure(message: message, code: code),
      storage: (message, code) => StorageFailure(message: message, code: code),
      validation: (message, code, field) =>
          ValidationFailure(message: message, code: code, field: field),
      parse: (message, code) => ParseFailure(message: message, code: code),
      cache: (message, code) => CacheFailure(message: message, code: code),
      service: (message, code) => ServiceFailure(message: message, code: code),
      unknown: (message, code) => ServerFailure(message: message, code: code),
    );
  }

  /// Creates appropriate failure based on HTTP status code.
  static AppFailure _createFailureFromStatusCode(
    int? statusCode,
    String message,
  ) {
    if (statusCode == null) {
      return ServerFailure(message: message, code: 500);
    }

    if (statusCode >= 400 && statusCode < 500) {
      // Client errors (4xx)
      if (statusCode == 401 || statusCode == 403) {
        return AuthFailure(message: message, code: statusCode);
      }
      return ServerFailure(message: message, code: statusCode);
    }

    // Server errors (5xx) or unknown
    return ServerFailure(message: message, code: statusCode);
  }

  /// Transforms Dio HTTP exceptions to failures
  static AppFailure _handleDioException(DioException exception) {
    switch (exception.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return const NetworkFailure(message: 'Connection timeout', code: 1003);

      case DioExceptionType.badResponse:
        final response = exception.response;
        return _createFailureFromStatusCode(
          response?.statusCode,
          _messageOf(response),
        );

      case DioExceptionType.cancel:
        return const ServerFailure(
          message: 'Request was cancelled',
          code: ErrorCodes.REQUEST_CANCELLED,
        );

      case DioExceptionType.connectionError:
        return const NetworkFailure(message: 'Connection error', code: 1005);

      case DioExceptionType.badCertificate:
        return const NetworkFailure(message: 'Certificate error', code: 1006);

      case DioExceptionType.transformTimeout:
        return const NetworkFailure(
          message: 'Transform timeout error',
          code: 1008,
        );

      case DioExceptionType.unknown:
        return NetworkFailure(
          message: exception.message ?? 'Unknown network error',
          code: 1007,
        );
    }
  }

  /// The user-facing message of an error response.
  ///
  /// Backends disagree on the shape of `message`: a plain string, a list of
  /// validation messages (NestJS's `{"message": ["email must be an
  /// email"]}`), an object, a number. Reading it as a `String` threw a
  /// `TypeError` for every shape but the first. Falls back to the HTTP
  /// status message, then to a generic one, when the body carries nothing
  /// usable — a non-map body included.
  static String _messageOf(Response<dynamic>? response) {
    final data = response?.data;
    final fromBody = data is Map ? _textOf(data['message']) : null;
    return fromBody ?? _textOf(response?.statusMessage) ?? 'Server error';
  }

  /// [value] as display text, or `null` when it holds none.
  ///
  /// A list is joined one entry per line, skipping entries with no text;
  /// anything else that is not a string goes through `toString`.
  static String? _textOf(Object? value) {
    if (value == null) return null;
    if (value is String) {
      final text = value.trim();
      return text.isEmpty ? null : text;
    }
    if (value is Iterable) {
      final lines = value.map(_textOf).whereType<String>();
      return lines.isEmpty ? null : lines.join('\n');
    }
    return _textOf(value.toString());
  }

  /// Creates a network failure for connection issues
  static NetworkFailure networkFailure([String? message]) {
    return NetworkFailure(
      message: message ?? 'Network connection failed',
      code: 1000,
    );
  }

  /// Creates a server failure for API errors
  static ServerFailure<T> serverFailure<T>([
    String? message,
    int? code,
    T? data,
  ]) {
    return ServerFailure(
      message: message ?? 'Server error occurred',
      code: code ?? 500,
      data: data,
    );
  }

  /// The failure for a response the server sent but the caller's success
  /// condition rejected — a 200 whose envelope reports an error.
  ///
  /// Coded [ErrorCodes.RESPONSE_REJECTED], never a 5xx: the server answered,
  /// so this is its verdict, not a transient fault. [message] is the
  /// envelope's own message when it carries one.
  static ServerFailure responseRejectedFailure([String? message]) {
    final text = message?.trim();
    return ServerFailure(
      message: (text == null || text.isEmpty)
          ? 'Request failed based on success condition'
          : text,
      code: ErrorCodes.RESPONSE_REJECTED,
    );
  }

  /// The failure for an empty response where a value was required.
  static ServerFailure emptyResponseFailure([String? message]) {
    return ServerFailure(
      message: message ?? 'Response data is null',
      code: ErrorCodes.EMPTY_RESPONSE,
    );
  }

  /// Creates an auth failure for authentication errors
  static AuthFailure authFailure([String? message, int? code]) {
    return AuthFailure(
      message: message ?? 'Authentication failed',
      code: code ?? 401,
    );
  }

  /// Creates a validation failure for input validation errors
  static ValidationFailure validationFailure(
    String message, {
    String? field,
    int? code,
  }) {
    return ValidationFailure(
      message: message,
      field: field,
      code: code ?? 3000,
    );
  }

  /// Creates a storage failure for local storage errors
  static StorageFailure storageFailure([String? message, int? code]) {
    return StorageFailure(
      message: message ?? 'Storage operation failed',
      code: code ?? 2000,
    );
  }

  /// Creates a parse failure for data parsing errors
  static ParseFailure parseFailure([String? message, int? code]) {
    return ParseFailure(
      message: message ?? 'Data parsing failed',
      code: code ?? 4000,
    );
  }

  /// Creates a cache failure for cache operation errors
  static CacheFailure cacheFailure([String? message, int? code]) {
    return CacheFailure(
      message: message ?? 'Cache operation failed',
      code: code ?? 5000,
    );
  }

  /// Creates a service failure for external service errors
  static ServiceFailure serviceFailure([String? message, int? code]) {
    return ServiceFailure(
      message: message ?? 'External service error',
      code: code ?? 6000,
    );
  }
}
