library base_provider;

import 'dart:async';

import 'package:core_common/core_common.dart';
import 'package:domain_core/domain_core.dart';
import 'package:flutter/foundation.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

export 'package:provider/provider.dart';

part '../management/operation_config.dart';
part '../management/operation_executor.dart';
part '../management/operation_global_config.dart';
part '../management/state_manager.dart';
part 'base_provider.freezed.dart';
part 'base_provider.g.dart';
part 'view_state_model.dart';

/// Clean and flexible base provider for state management
///
/// This base provider offers a clean, modular approach to state management
/// with separation of concerns and optional features that can be enabled as needed.
///
/// Key Features:
/// - Separation of concerns with dedicated state management
/// - Simplified operation execution with configuration objects
/// - Optional lifecycle and network monitoring
/// - Easy to test and extend
/// - Memory leak prevention with proper disposal
/// - Stream-based state broadcasting for reactive UI
///
/// Architecture:
/// - StateManager: Handles state transitions and notifications
/// - OperationExecutor: Manages operation execution and response processing
/// - OperationConfig: Configuration object for operations
///
/// Usage:
/// ```dart
/// class UserProvider extends BaseProvider<User> {
///   final GetUserUseCase _getUserUseCase;
///
///   UserProvider(this._getUserUseCase);
///
///   Future<void> loadUser(int id) async {
///     await executeOperation(OperationConfig(
///       operation: () => _getUserUseCase(GetUserParams(id: id)),
///       onSuccess: (user) => print('User loaded: ${user?.name}'),
///     ));
///   }
/// }
/// ```
abstract class BaseProvider<T> extends ChangeNotifier
    with LifecycleMixin, NetworkMixin {
  /// Creates a BaseProvider with optional monitoring features
  ///
  /// Parameters:
  /// - [enableLifecycleMonitoring]: Enable app lifecycle monitoring (default: false)
  /// - [enableNetworkMonitoring]: Enable network connectivity monitoring (default: false)
  ///
  /// The constructor automatically:
  /// - Initializes state management components
  /// - Sets up optional monitoring features
  /// - Schedules provider initialization after widget tree is ready
  BaseProvider({
    this._enableLifecycleMonitoring = false,
    this._enableNetworkMonitoring = false,
  }) : _stateManager = StateManager<T>() {
    // Initialize Operation executor with state manager
    _operationExecutor = OperationExecutor<T>(_stateManager);

    // Initialize monitoring if enabled
    if (_enableLifecycleMonitoring) {
      startListenOnLifecycleChange();
    }

    if (_enableNetworkMonitoring) {
      startListenOnNetworkConnect();
    }

    // Kick off initialize() after construction (constructor stays sync).
    // The returned Future is awaited here so ensureInitialized() only
    // resolves after subclass async setup finishes.
    Future.microtask(() async {
      if (isDisposed) return;
      try {
        await initialize();
      } catch (error, stackTrace) {
        // Keep ensureInitialized() unblocked, but surface the failure so
        // developers can see what went wrong during provider boot.
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'provider_state_management',
            context: ErrorDescription('while initializing $runtimeType'),
          ),
        );
      } finally {
        if (!_initializationCompleter.isCompleted) {
          _initializationCompleter.complete();
        }
      }
    });
  }

  final bool _enableLifecycleMonitoring;
  final bool _enableNetworkMonitoring;
  final StateManager<T> _stateManager;
  final Completer<void> _initializationCompleter = Completer<void>();
  late final OperationExecutor<T> _operationExecutor;

  /// Current view state containing state, data, and message
  ViewStateModel<T> get viewState => _stateManager.viewState;

  /// Current data from the view state
  T? get data => _stateManager.data;

  /// Check if currently in loading state
  bool get isLoading => _stateManager.isLoading;

  /// Check if currently in success state
  bool get isSuccess => _stateManager.isSuccess;

  /// Check if currently in error state
  bool get isError => _stateManager.isError;

  /// Check if provider is disposed
  bool get isDisposed => _stateManager.isDisposed;

  /// Stream of state changes for reactive programming
  ///
  /// This stream emits ViewStateModel updates whenever the state changes,
  /// allowing widgets to reactively update their UI.
  Stream<ViewStateModel<T>> get stateStream => _stateManager.stateStream;

  /// Listen to state changes with custom callbacks
  ///
  /// This method provides a convenient way to listen to state changes
  /// with proper error handling and cleanup options.
  ///
  /// Parameters:
  /// - [onData]: Callback for state change events
  /// - [cancelOnError]: Whether to cancel subscription on error
  /// - [onDone]: Callback when stream is closed
  /// - [onError]: Callback for stream errors
  ///
  /// Returns: StreamSubscription for manual management if needed
  StreamSubscription<ViewStateModel<T>> listen(
    void Function(ViewStateModel<T>) onData, {
    bool? cancelOnError,
    void Function()? onDone,
    Function? onError,
  }) {
    return _stateManager.stateStream.listen(
      onData,
      cancelOnError: cancelOnError,
      onDone: onDone,
      onError: onError,
    );
  }

  /// Update the current state
  ///
  /// This method provides a convenient way to update the provider state
  /// with individual parameters without creating ViewStateModel manually.
  ///
  /// Parameters:
  /// - [state]: New ViewState to set
  /// - [data]: New data to set
  /// - [message]: New message to set
  /// - [retainOldData]: Whether to keep existing data if no new data provided
  @protected
  void updateState({
    ViewState? state,
    T? data,
    String? message,
    bool retainOldData = true,
  }) {
    _stateManager.setState(
      state: state,
      data: data,
      message: message,
      retainOldData: retainOldData,
    );

    // Notify about state change
    if (state != null) {
      onStateChanged(state);
    }
  }

  /// Set data directly without changing state
  ///
  /// This method allows updating just the data while keeping
  /// the current state and message unchanged.
  @protected
  void setData(T? data) {
    _stateManager.setData(data);
  }

  /// Execute an Operation call with configuration
  ///
  /// This is the main method for executing Operation calls in a standardized way.
  /// It uses the OperationConfig pattern to reduce parameter complexity
  /// and provide a clean, readable Operation.
  ///
  /// Simplified to work with Result<R> directly.
  ///
  /// The method handles:
  /// - Loading state management
  /// - Response processing
  /// - Error handling and callbacks
  /// - State transitions
  ///
  /// Example:
  /// ```dart
  /// await executeOperation(OperationConfig(
  ///   operation: () => _useCase(params),
  ///   onSuccess: (data) => handleSuccess(data),
  ///   onFailure: (failure) => handleError(failure),
  /// ));
  /// ```
  @protected
  Future<void> executeOperation<R>(
    OperationConfig<R, T> config, {
    T? Function(R? data)? convert,
  }) async {
    await _operationExecutor.execute(config, convert);
  }

  /// Initialize the provider — override in subclasses.
  ///
  /// Called automatically via microtask after construction. Prefer awaiting
  /// all provider-specific setup here; [ensureInitialized] resolves only after
  /// this Future completes.
  ///
  /// Example:
  /// ```dart
  /// @override
  /// Future<void> initialize() async {
  ///   await super.initialize();
  ///   _subscription = listen(_onState);
  ///   await restoreSession();
  /// }
  /// ```
  ///
  /// UI / shell code should then:
  /// ```dart
  /// await provider.ensureInitialized();
  /// ```
  @protected
  @mustCallSuper
  Future<void> initialize() async {}

  /// Waits until [initialize] has finished (including subclass async work).
  ///
  /// Use this from boot / UI before relying on provider data.
  @mustCallSuper
  Future<void> ensureInitialized() async {
    if (_initializationCompleter.isCompleted) {
      return;
    }
    return _initializationCompleter.future;
  }

  /// Called when state changes - override in subclasses
  ///
  /// This method is called whenever the ViewState changes, allowing
  /// subclasses to react to state transitions.
  ///
  /// Common use cases:
  /// - Logging state changes
  /// - Triggering side effects
  /// - Updating related providers
  /// - Analytics tracking
  ///
  /// Parameters:
  /// - [state]: The new ViewState that was set
  ///
  /// Example:
  /// ```dart
  /// @override
  /// void onStateChanged(ViewState state) {
  ///   super.onStateChanged(state);
  ///
  ///   if (state == ViewState.success && data != null) {
  ///     // Handle successful data load
  ///   }
  /// }
  /// ```
  @protected
  void onStateChanged(ViewState state) {}

  /// Forward state manager notifications to ChangeNotifier
  @override
  void addListener(VoidCallback listener) {
    _stateManager.addListener(listener);
  }

  /// Forward state manager notifications to ChangeNotifier
  @override
  void removeListener(VoidCallback listener) {
    _stateManager.removeListener(listener);
  }

  /// Dispose resources and cleanup
  ///
  /// This method handles proper cleanup of all resources:
  /// - Stops lifecycle monitoring if enabled
  /// - Stops network monitoring if enabled
  /// - Disposes state manager and streams
  /// - Calls parent dispose
  ///
  /// Always call super.dispose() when overriding this method.
  @override
  void dispose() {
    if (_enableLifecycleMonitoring) {
      stopListenOnLifecycleChange();
    }

    if (_enableNetworkMonitoring) {
      stopListenOnNetworkConnect();
    }

    _stateManager.dispose();

    if (!_initializationCompleter.isCompleted) {
      _initializationCompleter.complete();
    }
    super.dispose();
  }

  /// Forward state manager notifications to ChangeNotifier
  @override
  void notifyListeners() {
    _stateManager.notifyListeners();
  }
}
