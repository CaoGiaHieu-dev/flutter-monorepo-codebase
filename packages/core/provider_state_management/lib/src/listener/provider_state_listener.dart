import 'dart:async';

import 'package:flutter/widgets.dart';

import '../base/base_provider.dart';

/// Callback type for when the provider transitions to the error state.
///
/// Parameters:
/// - [context]: The current build context
/// - [error]: The optional ErrorState attached to the error
/// - [message]: The optional error message
typedef OnErrorCallback<T> = void Function(
  BuildContext context,
  ErrorState? error,
  String? message,
);

/// Callback type for when the provider transitions to the success state.
typedef OnSuccessCallback<T> = void Function(BuildContext context, T? data);

/// Callback type for when the provider transitions to the loading state.
typedef OnLoadingCallback = void Function(BuildContext context);

/// Callback type for when any state change occurs.
typedef OnStateChangedCallback<T> = void Function(
  BuildContext context,
  ViewStateModel<T> state,
);

/// Callback type for filtering which state changes should trigger callbacks.
typedef ListenWhenCallback<T> = bool Function(
  ViewStateModel<T> previous,
  ViewStateModel<T> current,
);

/// A widget that listens to state changes from a [BaseProvider] and invokes
/// declarative callbacks for each state transition.
///
/// This widget eliminates the boilerplate of manually managing
/// [StreamSubscription], `initState`, and `dispose` when listening to
/// provider side-effects (toasts, navigation, dialogs, etc.).
///
/// **Key behaviors:**
/// - Automatically subscribes in `initState` and cancels in `dispose`
/// - Only fires callbacks when the state **actually changes** (not on rebuilds)
/// - Supports optional [listenWhen] filter for fine-grained control
///
/// Example:
/// ```dart
/// ProviderStateListener<AuthProvider, UserEntity>(
///   onError: (context, error, message) {
///     if (error is AuthErrorState) {
///       error.maybeWhen(
///         invalidCredentials: () => showToast('Invalid credentials'),
///         orElse: () => showToast(message ?? 'Error'),
///       );
///     }
///   },
///   child: Scaffold(...),
/// )
/// ```
class ProviderStateListener<P extends BaseProvider<T>, T>
    extends StatefulWidget {
  /// Creates a [ProviderStateListener].
  ///
  /// The [child] widget is required and will be rendered as-is.
  /// At least one callback should be provided for the listener to be useful.
  const ProviderStateListener({
    super.key,
    required this.child,
    this.onLoading,
    this.onSuccess,
    this.onError,
    this.onStateChanged,
    this.listenWhen,
    this.onLoadingMore,
  });

  /// The child widget to render. This widget is NOT rebuilt by the listener.
  final Widget child;

  /// Called when the provider transitions to the loading state.
  final OnLoadingCallback? onLoading;

  /// Called when the provider transitions to the loadingMore state.
  final OnLoadingCallback? onLoadingMore;

  /// Called when the provider transitions to the success state.
  /// Receives the current data from the provider.
  final OnSuccessCallback<T>? onSuccess;

  /// Called when the provider transitions to the error state.
  /// Receives the [ErrorState] and optional message.
  final OnErrorCallback<T>? onError;

  /// Called on every state change. Use this for generic state observation.
  /// This is called BEFORE the specific state callbacks (onLoading, etc.).
  final OnStateChangedCallback<T>? onStateChanged;

  /// Optional filter to control which state changes trigger callbacks.
  ///
  /// If provided, callbacks are only invoked when this returns `true`.
  /// If not provided, callbacks are invoked on every state change.
  final ListenWhenCallback<T>? listenWhen;

  @override
  State<ProviderStateListener<P, T>> createState() =>
      _ProviderStateListenerState<P, T>();
}

class _ProviderStateListenerState<P extends BaseProvider<T>, T>
    extends State<ProviderStateListener<P, T>> {
  StreamSubscription<ViewStateModel<T>>? _subscription;
  late ViewStateModel<T> _previousState;

  @override
  void initState() {
    super.initState();
    final provider = context.read<P>();
    _previousState = provider.viewState;
    _subscription = provider.listen(_onStateChanged);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    super.dispose();
  }

  void _onStateChanged(ViewStateModel<T> currentState) {
    // Skip if state hasn't actually changed
    if (_previousState == currentState) return;

    // Apply optional filter
    if (widget.listenWhen != null &&
        !widget.listenWhen!(_previousState, currentState)) {
      _previousState = currentState;
      return;
    }

    _previousState = currentState;

    // Fire generic state changed callback first
    widget.onStateChanged?.call(context, currentState);

    // Fire specific state callbacks
    currentState.state.when(
      initial: () {
        /// Do nothing for initial state
      },
      loading: () => widget.onLoading?.call(context),
      success: () => widget.onSuccess?.call(context, currentState.data),
      error: (error) =>
          widget.onError?.call(context, error, currentState.message),
      loadingMore: () => widget.onLoadingMore?.call(context),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// An abstract base for listener entries used in [MultiProviderStateListener].
abstract class ProviderStateListenerBase {
  const ProviderStateListenerBase();

  /// Builds the listener wrapping the given [child].
  Widget buildWithChild(BuildContext context, Widget child);
}

/// A configuration entry for a state listener inside [MultiProviderStateListener].
///
/// Example:
/// ```dart
/// MultiProviderStateListener(
///   listeners: [
///     ProviderStateListenerEntry<AuthProvider, UserEntity>(
///       onError: (context, error, message) => showToast(message),
///     ),
///     ProviderStateListenerEntry<CartProvider, Cart>(
///       onSuccess: (context, data) => showToast('Cart updated'),
///     ),
///   ],
///   child: Scaffold(...),
/// )
/// ```
class ProviderStateListenerEntry<P extends BaseProvider<T>, T>
    extends ProviderStateListenerBase {
  const ProviderStateListenerEntry({
    this.onLoading,
    this.onSuccess,
    this.onError,
    this.onStateChanged,
    this.listenWhen,
    this.onLoadingMore,
  });

  final OnLoadingCallback? onLoading;
  final OnLoadingCallback? onLoadingMore;
  final OnSuccessCallback<T>? onSuccess;
  final OnErrorCallback<T>? onError;
  final OnStateChangedCallback<T>? onStateChanged;
  final ListenWhenCallback<T>? listenWhen;

  @override
  Widget buildWithChild(BuildContext context, Widget child) {
    return ProviderStateListener<P, T>(
      onLoading: onLoading,
      onSuccess: onSuccess,
      onError: onError,
      onStateChanged: onStateChanged,
      listenWhen: listenWhen,
      onLoadingMore: onLoadingMore,
      child: child,
    );
  }
}
