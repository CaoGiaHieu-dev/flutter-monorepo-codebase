import 'failures.dart';

/// Maps an error type the kernel cannot see to an [AppFailure].
///
/// The kernel is the dependency of every package, so it names no transport,
/// plugin or SDK exception type itself — its dependency list would become
/// everyone's. A package that owns such a type (`core_network` owns Dio's
/// `DioException`) implements this and hands it to
/// `ErrorHandler.registerClassifier`; `ErrorHandler.handleError` then asks
/// every registered classifier, in registration order, before its own
/// `dart:io` / `FormatException` rules and the generic fallback.
///
/// ```dart
/// final class GrpcFailureClassifier implements ErrorClassifier {
///   const GrpcFailureClassifier();
///
///   @override
///   AppFailure<dynamic>? classify(Object error) => error is GrpcError
///       ? NetworkFailure(message: error.message ?? 'gRPC error', code: 1010)
///       : null;
/// }
/// ```
abstract interface class ErrorClassifier {
  /// The failure for [error], or `null` when [error] is not this
  /// classifier's to map — the next classifier, then the kernel's own rules,
  /// get it.
  ///
  /// May throw; `ErrorHandler.handleError` never does, and degrades a
  /// throwing classifier to the generic unknown-error failure.
  AppFailure<dynamic>? classify(Object error);
}
