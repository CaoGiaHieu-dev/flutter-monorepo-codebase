part of '../base/base_provider.dart';

/// Global configuration for Operation execution callbacks.
///
/// This allows defining default behaviors (like showing error dialogs)
/// across the entire application without repeating code in every provider.
///
/// The callbacks are exposed read-only on purpose: they may only be changed
/// through [setup] (which merges) or cleared through [reset]. Assigning them
/// directly used to be possible and made it impossible to reason about who
/// installed a given hook.
class OperationGlobalConfig {
  OperationGlobalConfig._();

  static final instance = OperationGlobalConfig._();

  void Function()? _onStart;
  void Function(dynamic data)? _onSuccess;
  void Function(AppFailure failure)? _onFailure;
  void Function()? _onFinish;

  /// Default callback when an operation starts (e.g., global logging)
  void Function()? get onStart => _onStart;

  /// Default callback when an operation succeeds
  void Function(dynamic data)? get onSuccess => _onSuccess;

  /// Default callback when an operation fails (e.g., showing a global error dialog)
  void Function(AppFailure failure)? get onFailure => _onFailure;

  /// Default callback when an operation finishes (regardless of success/failure)
  void Function()? get onFinish => _onFinish;

  /// Installs global hooks, **merging** with whatever is already configured.
  ///
  /// Only the callbacks you pass are replaced; the ones you omit keep their
  /// current value. That makes it safe to call [setup] from more than one
  /// place (for example a bootstrap step plus a flavor-specific override)
  /// without silently wiping hooks installed earlier.
  ///
  /// Passing `null` for a parameter is treated as "leave unchanged", not as
  /// "clear" — use [reset] to clear everything.
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
    _onStart = onStart ?? _onStart;
    _onSuccess = onSuccess ?? _onSuccess;
    _onFailure = onFailure ?? _onFailure;
    _onFinish = onFinish ?? _onFinish;
  }

  /// Clears every installed hook.
  ///
  /// Because [instance] is a process-wide singleton, tests that install hooks
  /// must call this in their teardown, otherwise the hooks leak into every
  /// later test in the same run.
  @visibleForTesting
  void reset() {
    _onStart = null;
    _onSuccess = null;
    _onFailure = null;
    _onFinish = null;
  }
}
