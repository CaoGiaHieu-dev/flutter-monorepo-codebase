import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

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
  static AppFailure handleError(dynamic error, [StackTrace? stackTrace]) {
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
      message: kDebugMode ? error.toString() : 'Unknown error occurred',
      code: 9999,
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
        final statusCode = exception.response?.statusCode;
        String message = 'Server error';
        if (exception.response?.data is Map?) {
          message =
              exception.response?.data?['message'] ??
              exception.response?.statusMessage ??
              'Server error';
        } else {
          message = exception.response?.statusMessage ?? 'Server error';
        }

        return _createFailureFromStatusCode(statusCode, message);

      case DioExceptionType.cancel:
        return const ServerFailure(
          message: 'Request was cancelled',
          code: 1004,
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
