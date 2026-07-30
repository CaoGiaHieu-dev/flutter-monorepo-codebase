part of '../base/base_provider.dart';

/// Global configuration for Operation execution callbacks.
///
/// This allows defining default behaviors (like showing error dialogs)
/// across the entire application without repeating code in every provider.
class OperationGlobalConfig {
  OperationGlobalConfig._();

  static final instance = OperationGlobalConfig._();

  /// Default callback when an operation starts (e.g., global logging)
  void Function()? onStart;

  /// Default callback when an operation succeeds
  void Function(dynamic data)? onSuccess;

  /// Default callback when an operation fails (e.g., showing a global error dialog)
  void Function(AppFailure failure)? onFailure;

  /// Default callback when an operation finishes (regardless of success/failure)
  void Function()? onFinish;

  /// Setup the global configuration
  ///
  /// Example:
  /// ```dart
  /// OperationGlobalConfig.instance.setup(
  ///   onFailure: (failure) => AppDialog.showErrorDialog(message: failure.message),
  /// );
  /// ```
  void setup({
    void Function()? onStart,
    void Function(dynamic data)? onSuccess,
    void Function(AppFailure failure)? onFailure,
    void Function()? onFinish,
  }) {
    this.onStart = onStart;
    this.onSuccess = onSuccess;
    this.onFailure = onFailure;
    this.onFinish = onFinish;
  }
}
