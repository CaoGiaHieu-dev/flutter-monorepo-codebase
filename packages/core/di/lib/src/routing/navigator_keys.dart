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
/// shell to read a key. Hosting them here in `core_di` — which both sides
/// already depend on — breaks that cycle.
///
/// ## Why a feature-named key ([authKey]) is allowed here
///
/// [authKey] names a specific feature, which normally would be a layering
/// smell. It is permitted because this class is *routing plumbing*, not
/// business logic: the key is only an identity token handed to GoRouter. The
/// DI Hub never imports `feature_auth`, and `feature_auth` never imports the
/// app shell — they meet on this neutral key.
///
/// Add a key here only when a feature genuinely needs its own nested
/// [Navigator] (its own back stack). Tabs that live in the dashboard
/// `StatefulShellRoute` get their branch navigator from GoRouter and do **not**
/// need an entry.
///
/// Consumers:
/// - [rootKey] — `AppRouter`'s top-level `GoRouter.navigatorKey`
/// - [appKey] — the app `ShellRoute`; parent of `feature_auth` /
///   `feature_onboarding` top-level routes
/// - [authKey] — `feature_auth`'s own nested navigator (login / register /
///   forgot-password share one back stack)
class NavigatorKeys {
  NavigatorKeys._();

  /// Navigator for the app [ShellRoute] that wraps all in-app routes.
  static final appKey = GlobalKey<NavigatorState>();

  /// Root navigator owned by `GoRouter` itself — used for full-screen routes
  /// that must escape the app shell.
  static final rootKey = GlobalKey<NavigatorState>();

  /// Nested navigator owned by `feature_auth`, giving the auth flow its own
  /// back stack.
  static final authKey = GlobalKey<NavigatorState>();
}
