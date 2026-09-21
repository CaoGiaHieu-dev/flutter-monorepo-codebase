part of '../base/base_provider.dart';

/// Handles operation execution and response processing
///
/// This class is responsible for executing operations (API calls, database operations,
/// file operations, etc.) and processing their responses according to the provided configuration.
///
/// Simplified to work with Result<R> directly instead of BaseResult<R>.
///
/// Features:
/// - Handles loading state management
/// - Processes success and error responses
/// - Manages state transitions during operations
/// - Provides comprehensive error handling
class OperationExecutor<T> {
  const OperationExecutor(this._stateManager);

  final StateManager<T> _stateManager;

  /// Execute an operation with the given configuration
  ///
  /// This is the main method that orchestrates the entire operation flow:
  /// 1. Handle loading state
  /// 2. Execute the operation
  /// 3. Process the response (Success or Failure)
  ///
  /// Simplified to work directly with Result<R> pattern.
  Future<void> execute<R>(
    OperationConfig<R, T> config,
    T? Function(R? data)? convert,
  ) async {
    if (_stateManager.isDisposed) return;

    // Execute global onStart hook
    OperationGlobalConfig.instance.onStart?.call();

    // Show loading state if configured
    if (config.showLoading && _stateManager.data == null) {
      _stateManager.setState(state: const ViewState.loading());
    }

    // Execute operation
    final result = await config.operation();

    if (_stateManager.isDisposed) return;

    // Await the whenAsync call to handle async branches correctly.
    await result.whenAsync(
      success: (data) => _handleSuccess(data, config, convert: convert),
      failure: (failure) => _handleFailure(failure, config),
      none: _handleNone,
      cancel: _handleCancel,
    );

    // Execute global onFinish hook
    OperationGlobalConfig.instance.onFinish?.call();
  }

  /// Handle successful response
  Future<void> _handleSuccess<R>(
    R? data,
    OperationConfig<R, T> config, {
    T? Function(R? data)? convert,
  }) async {
    if (_stateManager.isDisposed) return;

    T? finalData;

    if (convert != null) {
      finalData = convert(data);
    } else if (data is T) {
      finalData = data;
    } else if (data == null) {
      finalData = null;
    } else {
      assert(
        false,
        'A `convert` function must be provided to `executeOperation` when the operation result type ($R) is not assignable to the provider\'s state type ($T).',
      );
    }

    _stateManager.setState(state: const ViewState.success(), data: finalData);

    // Execute local callback if provided, otherwise execute global callback
    if (config.onSuccess != null) {
      await config.onSuccess?.call(finalData);
    } else {
      OperationGlobalConfig.instance.onSuccess?.call(finalData);
    }
  }

  /// Handle failure response
  Future<void> _handleFailure<R>(
    AppFailure failure,
    OperationConfig<R, T> config,
  ) async {
    if (_stateManager.isDisposed) return;

    final errorState = config.errorStateBuilder?.call(failure);
    _stateManager.setState(
      state: ViewState.error(error: errorState),
      message: failure.message,
    );

    // Execute local callback if provided, otherwise execute global callback
    if (config.onFailure != null) {
      await config.onFailure?.call(failure);
    } else {
      OperationGlobalConfig.instance.onFailure?.call(failure);
    }
  }

  /// Handle a 'None' result.
  ///
  /// This method is called when an operation results in a no-op. It intentionally
  /// does nothing to the state, ensuring that the UI remains in its current
  /// state without transitioning to an error or success state.
  void _handleNone() {
    if (_stateManager.isDisposed) return;
    // No state change is needed for a 'None' result.
    // It signifies a no-op, so we keep the UI as is.
  }

  /// Handle cancelled response
  ///
  /// This method is called when an operation is cancelled. It intentionally
  /// does nothing to the state, ensuring that the UI remains in its current
  /// state without transitioning to an error or success state.
  void _handleCancel() {
    if (_stateManager.isDisposed) return;
    // No state change is needed when an operation is cancelled.
  }
}
