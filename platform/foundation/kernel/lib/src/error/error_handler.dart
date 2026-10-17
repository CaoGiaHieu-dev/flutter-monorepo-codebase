import 'dart:io';

import '../utils/error_codes.dart';
import 'error_classifier.dart';
import 'exceptions.dart';
import 'failures.dart';

/// Global error handler for transforming exceptions to failures
///
/// This utility class provides centralized error handling and transformation
/// logic for converting platform-specific exceptions into domain failures.
/// It ensures consistent error handling across all layers of the application.
///
/// The error handler follows these transformation rules:
/// - [AppException]s → the matching failure
/// - Types a registered [ErrorClassifier] recognises → its failure (the
///   kernel names no transport type: `core_network` registers the Dio
///   classifier — timeouts/connection → NetworkFailure, HTTP error
///   responses → ServerFailure / AuthFailure)
/// - Network-related `dart:io` exceptions → NetworkFailure
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
  /// an exception escaping this method would escape `BaseRepository.execute`
  /// too — and a caller awaiting a `Result` (a provider in its loading state)
  /// would never get one. Anything that goes wrong while classifying [error]
  /// therefore degrades to the generic unknown-error failure.
  static AppFailure<dynamic> handleError(
    dynamic error, [
    StackTrace? stackTrace,
  ]) {
    try {
      return _classify(error, stackTrace);
    } catch (_) {
      _notifyUnclassified(error, stackTrace);
      return const ServerFailure(
        message: _unknownMessage,
        code: ErrorCodes.UNKNOWN,
      );
    }
  }

  /// The classifiers [handleError] asks before its own rules — see
  /// [ErrorClassifier]. Registered by the package that owns the error type,
  /// from its DI module (`core_network` registers `DioFailureClassifier`
  /// while the `core` DI group initialises, before any request is made).
  static final List<ErrorClassifier> _classifiers = [];

  /// Adds [classifier] after those already registered.
  ///
  /// Idempotent per type: registering a second instance of the same runtime
  /// type replaces the first in place, so a module initialised twice (a test
  /// that runs `configureDependencies` per case) never stacks copies.
  static void registerClassifier(ErrorClassifier classifier) {
    final index = _classifiers.indexWhere(
      (c) => c.runtimeType == classifier.runtimeType,
    );
    if (index == -1) {
      _classifiers.add(classifier);
    } else {
      _classifiers[index] = classifier;
    }
  }

  /// Removes every registered classifier of [classifier]'s runtime type.
  /// Returns whether one was registered.
  static bool unregisterClassifier(ErrorClassifier classifier) {
    final before = _classifiers.length;
    _classifiers.removeWhere((c) => c.runtimeType == classifier.runtimeType);
    return _classifiers.length != before;
  }

  /// The registered classifiers, in the order [handleError] asks them.
  static List<ErrorClassifier> get classifiers =>
      List.unmodifiable(_classifiers);

  /// Called with every error [handleError] could not classify — the ones
  /// that become the generic "Unknown error occurred" failure.
  ///
  /// A `SocketException` or a 401 is an expected failure; an exception of a
  /// type nobody mapped (a `TypeError` in a `fromJson`, a plugin exception)
  /// usually is a bug, and the user only ever sees "unknown error" for it.
  /// This is the seam that lets such a failure be reported while it is still
  /// handled: the app shell (`runShellApp`) points it at the optional
  /// `IErrorReporter` as a non-fatal error. The kernel is pure Dart and
  /// declares no `core_di` dependency, so it exposes a plain callback rather
  /// than resolving the contract itself.
  ///
  /// [stackTrace] is the one passed to [handleError], or the current trace
  /// when the caller passed none. The listener must not throw; if it does,
  /// the error is swallowed — [handleError] never throws.
  static void Function(Object error, StackTrace stackTrace)?
  onUnclassifiedError;

  static void _notifyUnclassified(Object? error, StackTrace? stackTrace) {
    final listener = onUnclassifiedError;
    if (listener == null || error == null) return;
    try {
      listener(error, stackTrace ?? StackTrace.current);
    } catch (_) {
      // Reporting is best-effort; a failing reporter must not turn a
      // handled failure into an exception.
    }
  }

  /// Message of the generic failure shown in release builds.
  static const String _unknownMessage = 'Unknown error occurred';

  /// The classification behind [handleError]; may throw on a hostile
  /// [error] (a `toString` that throws, say), which [handleError] absorbs.
  static AppFailure<dynamic> _classify(dynamic error, StackTrace? stackTrace) {
    // Handle custom application exceptions
    if (error is AppException) {
      return _handleAppException(error);
    }

    // Types owned by other packages (Dio's `DioException`, registered by
    // `core_network`), asked in registration order.
    if (error is Object) {
      for (final classifier in _classifiers) {
        final failure = classifier.classify(error);
        if (failure != null) return failure;
      }
    }

    // Handle platform-specific exceptions
    if (error is SocketException) {
      return const NetworkFailure(
        message: 'No internet connection',
        code: ErrorCodes.NO_INTERNET,
      );
    }

    if (error is HttpException) {
      return NetworkFailure(
        message: 'Network error: ${error.message}',
        code: ErrorCodes.HTTP_ERROR,
      );
    }

    if (error is FormatException) {
      return ParseFailure(
        message: 'Invalid data format: ${error.message}',
        code: ErrorCodes.INVALID_FORMAT,
      );
    }

    // Handle generic exceptions. The failure is built first: a `toString`
    // that throws lands in [handleError]'s catch, which notifies once.
    final failure = ServerFailure<dynamic>(
      message: _isDebug ? error.toString() : _unknownMessage,
      code: ErrorCodes.UNKNOWN,
    );
    _notifyUnclassified(error, stackTrace);
    return failure;
  }

  /// Transforms custom application exceptions to failures
  static AppFailure<dynamic> _handleAppException(AppException exception) {
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

  /// Creates a network failure for connection issues
  static NetworkFailure<dynamic> networkFailure([String? message]) {
    return NetworkFailure(
      message: message ?? 'Network connection failed',
      code: ErrorCodes.NETWORK_ERROR,
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
  static ServerFailure<dynamic> responseRejectedFailure([String? message]) {
    final text = message?.trim();
    return ServerFailure(
      message: (text == null || text.isEmpty)
          ? 'Request failed based on success condition'
          : text,
      code: ErrorCodes.RESPONSE_REJECTED,
    );
  }

  /// The failure for an empty response where a value was required.
  static ServerFailure<dynamic> emptyResponseFailure([String? message]) {
    return ServerFailure(
      message: message ?? 'Response data is null',
      code: ErrorCodes.EMPTY_RESPONSE,
    );
  }

  /// Creates an auth failure for authentication errors
  static AuthFailure<dynamic> authFailure([String? message, int? code]) {
    return AuthFailure(
      message: message ?? 'Authentication failed',
      code: code ?? 401,
    );
  }

  /// Creates a validation failure for input validation errors
  static ValidationFailure<dynamic> validationFailure(
    String message, {
    String? field,
    int? code,
  }) {
    return ValidationFailure(
      message: message,
      field: field,
      code: code ?? ErrorCodes.VALIDATION_ERROR,
    );
  }

  /// Creates a storage failure for local storage errors
  static StorageFailure<dynamic> storageFailure([String? message, int? code]) {
    return StorageFailure(
      message: message ?? 'Storage operation failed',
      code: code ?? ErrorCodes.STORAGE_ERROR,
    );
  }

  /// Creates a parse failure for data parsing errors
  static ParseFailure<dynamic> parseFailure([String? message, int? code]) {
    return ParseFailure(
      message: message ?? 'Data parsing failed',
      code: code ?? ErrorCodes.PARSE_ERROR,
    );
  }

  /// Creates a cache failure for cache operation errors
  static CacheFailure<dynamic> cacheFailure([String? message, int? code]) {
    return CacheFailure(
      message: message ?? 'Cache operation failed',
      code: code ?? ErrorCodes.CACHE_ERROR,
    );
  }

  /// Creates a service failure for external service errors
  static ServiceFailure<dynamic> serviceFailure([String? message, int? code]) {
    return ServiceFailure(
      message: message ?? 'External service error',
      code: code ?? ErrorCodes.SERVICE_ERROR,
    );
  }
}
