import 'package:material_ui/material_ui.dart';

/// Globally shared [GlobalKey]s for the app's nested / shell navigators.
///
/// ## Why the DI Hub owns these keys
///
/// A `ShellRoute` and its child routes must reference the *same*
/// [GlobalKey<NavigatorState>] instance. The shell is assembled by the app
/// shell (`AppRouter`), while the child routes are declared inside feature
/// packages — so both sides need one shared instance.
///
/// Putting the keys in either side would create a cycle: the app shell already
/// depends on every feature package, so a feature cannot depend back on the app
/// shell to read a key. Hosting them here — which both sides already depend
/// on — breaks that cycle.
///
/// ## Nested keys are requested by id, not declared here
///
/// This class used to expose `authKey`, naming one specific feature from an
/// infra package. Every feature that wanted its own back stack had to open a PR
/// against the DI Hub, and the DI Hub's public surface grew a product vocabulary
/// it has no business knowing.
///
/// [nested] replaces that: a module asks for a key by id and gets the same
/// instance every time, so the shell and its children agree without anyone
/// declaring anything centrally.
///
/// ```dart
/// class CheckoutShellRoute extends ShellRouteData {
///   static final $navigatorKey = NavigatorKeys.nested('checkout');
/// }
/// ```
///
/// Ask for one only when a module genuinely needs its own [Navigator] — its own
/// back stack. Destinations inside the app's `StatefulShellRoute` get a branch
/// navigator from GoRouter and need no key.
class NavigatorKeys {
  NavigatorKeys._();

  /// Navigator for the app [ShellRoute] that wraps all in-app routes.
  static final appKey = GlobalKey<NavigatorState>(debugLabel: 'app');

  /// Root navigator owned by `GoRouter` itself — used for full-screen routes
  /// that must escape the app shell.
  static final rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');

  static final _nested = <String, GlobalKey<NavigatorState>>{};

  /// The nested navigator key registered under [id], created on first use.
  ///
  /// Returns the *same* instance for the same id — which is the whole
  /// requirement, since a shell route and its children must share one.
  static GlobalKey<NavigatorState> nested(String id) => _nested.putIfAbsent(
    id,
    () => GlobalKey<NavigatorState>(debugLabel: 'nested:$id'),
  );
}
