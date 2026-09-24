/// Product analytics — Firebase Analytics, Amplitude, Mixpanel, …
///
/// ## Optional by design
///
/// Nothing in the template implements it. Callers resolve it with
/// `getItOrNull<IAnalytics>()` and do nothing when it is `null`, so an app
/// without analytics composes no extra package and no call site changes.
///
/// `core_common`'s `RouteAwareWidget` — the wrapper every
/// `GoRouteDataCustom` page gets — already reports each screen through
/// [setCurrentScreen] when a route is pushed and when it becomes visible
/// again after the route above it pops.
///
/// ## Owner side
///
/// ```dart
/// @LazySingleton(as: IAnalytics)
/// class FirebaseAnalyticsImpl implements IAnalytics {
///   @override
///   Future<void> logEvent(String name, {Map<String, Object>? parameters}) =>
///       FirebaseAnalytics.instance.logEvent(
///         name: name,
///         parameters: parameters,
///       );
///
///   @override
///   Future<void> setCurrentScreen(String screenName) =>
///       FirebaseAnalytics.instance.logScreenView(screenName: screenName);
/// }
/// ```
///
/// A contract carries plain values only — never a vendor type — so a feature
/// can log an event without depending on the analytics SDK.
abstract class IAnalytics {
  /// Logs a custom event named [name] with optional [parameters].
  Future<void> logEvent(String name, {Map<String, Object>? parameters});

  /// Records that [screenName] is now the screen on top.
  Future<void> setCurrentScreen(String screenName);
}
