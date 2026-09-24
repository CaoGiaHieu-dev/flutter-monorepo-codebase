import 'package:flutter/widgets.dart';

import 'provider_state_listener.dart';

/// A widget that composes multiple [ProviderStateListenerEntry] widgets
/// into a single nested tree.
///
/// This eliminates deep nesting when listening to multiple providers
/// for side-effects on the same page.
///
/// Example:
/// ```dart
/// MultiProviderStateListener(
///   listeners: [
///     ProviderStateListenerEntry<AuthProvider, UserEntity>(
///       onError: (context, error, message) {
///         showToast(message ?? 'Auth error');
///       },
///     ),
///     ProviderStateListenerEntry<CartProvider, Cart>(
///       onSuccess: (context, data) {
///         showToast('Cart updated!');
///       },
///     ),
///   ],
///   child: Scaffold(...),
/// )
/// ```
class MultiProviderStateListener extends StatelessWidget {
  /// Creates a [MultiProviderStateListener].
  ///
  /// The [listeners] list must not be empty.
  /// Each listener entry is nested automatically with the [child] at the bottom.
  const MultiProviderStateListener({
    super.key,
    required this.listeners,
    required this.child,
  });

  /// The list of [ProviderStateListenerBase] entries to compose.
  ///
  /// Each entry defines which provider to listen to and what callbacks
  /// to invoke on state changes.
  final List<ProviderStateListenerBase> listeners;

  /// The child widget that will be wrapped by all listeners.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Build the nested listener tree from bottom to top
    Widget current = child;
    for (final listener in listeners.reversed) {
      current = listener.buildWithChild(context, current);
    }
    return current;
  }
}
