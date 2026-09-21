/// Custom exceptions for the application
///
/// This file defines custom exception classes that represent different
/// types of errors that can occur in the application. These exceptions
/// are typically caught and transformed into [AppFailure] instances
/// for consistent error handling across layers.
///
/// The exception hierarchy follows the same structure as the failure
/// hierarchy to maintain consistency in error handling patterns.
library;

import 'package:freezed_annotation/freezed_annotation.dart';

part 'exceptions.freezed.dart';

/// Base class for all application exceptions
///
/// This sealed class serves as the foundation for all custom exceptions
/// in the application. It provides a consistent interface for exception
/// handling and includes optional error codes for categorization.
///
/// Example usage:
/// ```dart
/// try {
///   await riskyOperation();
/// } catch (e) {
///   if (e is AppException) {
///     return Failure(NetworkFailure(message: e.message, code: e.code));
///   }
///   rethrow;
/// }
/// ```
@freezed
sealed class AppException with _$AppException implements Exception {
  const AppException._();

  /// Exception thrown during network operations
  const factory AppException.network(String message, {int? code}) =
      NetworkException;

  /// Exception thrown when server returns an error response
  const factory AppException.server(String message, {int? code}) =
      ServerException;

  /// Exception thrown during authentication or authorization
  const factory AppException.auth(String message, {int? code}) = AuthException;

  /// Exception thrown during local storage operations
  const factory AppException.storage(String message, {int? code}) =
      StorageException;

  /// Exception thrown during data validation
  const factory AppException.validation(
    String message, {
    int? code,
    String? field,
  }) = ValidationException;

  /// Exception thrown during data parsing or serialization
  const factory AppException.parse(String message, {int? code}) =
      ParseException;

  /// Exception thrown during cache operations
  const factory AppException.cache(String message, {int? code}) =
      CacheException;

  /// Exception thrown during external service operations
  const factory AppException.service(String message, {int? code}) =
      ServiceException;

  /// Fallback or unknown exception type
  const factory AppException.unknown(String message, {int? code}) =
      UnknownException;

  @override
  String toString() {
    return when(
      network: (message, code) =>
          'NetworkException: $message${code != null ? ' (Code: $code)' : ''}',
      server: (message, code) =>
          'ServerException: $message${code != null ? ' (Code: $code)' : ''}',
      auth: (message, code) =>
          'AuthException: $message${code != null ? ' (Code: $code)' : ''}',
      storage: (message, code) =>
          'StorageException: $message${code != null ? ' (Code: $code)' : ''}',
      validation: (message, code, field) =>
          'ValidationException: $message${field != null ? ' (Field: $field)' : ''}${code != null ? ' (Code: $code)' : ''}',
      parse: (message, code) =>
          'ParseException: $message${code != null ? ' (Code: $code)' : ''}',
      cache: (message, code) =>
          'CacheException: $message${code != null ? ' (Code: $code)' : ''}',
      service: (message, code) =>
          'ServiceException: $message${code != null ? ' (Code: $code)' : ''}',
      unknown: (message, code) =>
          'UnknownException: $message${code != null ? ' (Code: $code)' : ''}',
    );
  }
}
