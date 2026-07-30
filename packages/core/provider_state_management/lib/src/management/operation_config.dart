part of '../base/base_provider.dart';

/// Configuration class for asynchronous operations to reduce parameter complexity
///
/// This class encapsulates all the parameters needed for executing operations,
/// making the execution cleaner and more maintainable. It supports various types
/// of operations including API calls, database operations, file operations, etc.
///
/// Simplified to work with Result<R> directly instead of BaseResult<R>.
///
/// Example usage:
/// ```dart
/// final config = OperationConfig<UserEntity>(
///   operation: () => _getUserUseCase(params),
///   onSuccess: (user) => print('Success: ${user.name}'),
///   onFailure: (failure) => print('Error: ${failure.message}'),
/// );
/// ```
class OperationConfig<R, T> {
  const OperationConfig({
    required this.operation,
    this.onSuccess,
    this.onFailure,
    this.showLoading = true,
    this.errorStateBuilder,
  });

  /// The operation function to execute (API call, database operation, etc.)
  /// Now returns Result<R> directly instead of BaseResult<R>
  final FutureOr<Result<R>> Function() operation;

  /// Optional callback when operation succeeds with data
  final FutureOr<void> Function(T? data)? onSuccess;

  /// Optional callback when operation fails with system failure
  final FutureOr<void> Function(AppFailure failure)? onFailure;

  /// Whether to show loading state (default: true)
  final bool showLoading;

  /// Optional builder to map failure to ErrorState
  final ErrorState? Function(AppFailure failure)? errorStateBuilder;
}
