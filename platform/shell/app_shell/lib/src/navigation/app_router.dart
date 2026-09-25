import 'package:core_common/core_common.dart';
import 'package:core_di/core_di.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:injectable/injectable.dart';
import 'package:material_ui/material_ui.dart';
import 'package:platform_shell_adapters/platform_shell_adapters.dart';

import '../widgets/navigator_wrapper_widget.dart';
import '../widgets/undefine_route_widget.dart';

/// Dynamic and decentralized application routing manager.
///
/// Assembles GoRouter from DI contributions:
/// - [IFeatureRouteModule] — top-level feature routes (onboarding, auth, …)
/// - [INavDestinationModule] — primary destinations + their shell branches
/// - [IDashboardRouteModule] — dashboard chrome (optional)
/// - [IAppEntryLocation] — first-launch path (optional)
///
/// ([ISignInLocation] / [IPostSignInLocation] are not read here: they are
/// where `NavigatorWrapperWidget` sends a user when the session changes.)
///
/// Missing modules fall back to empty routes / a chromeless shell /
/// [fallbackLocation] (the first destination, else `/_empty_dashboard`).
///
/// Every contribution is resolved optionally and this file imports no feature
/// package, so removing any feature leaves routing intact — including
/// [ISessionRefreshListenable], which simply resolves to `null` when no module
/// owns a session (the router then never refreshes on session changes, which
/// is correct when there are none).
@singleton
class AppRouter {
  /// Observes every navigator the router builds: attached to the root
  /// navigator through `GoRouter(observers:)`, and go_router forwards the
  /// root observers to each `ShellRoute` and `StatefulShellBranch` navigator
  /// (`notifyRootObserver`, on by default) — so one instance sees the whole
  /// app. `AppInitializer.init` hands it to `RouteAwareWidget`.
  final routeObserver = RouteObserver<ModalRoute<void>>();

  BuildContext get currentContext {
    final context = router.routerDelegate.navigatorKey.currentContext;
    if (context?.mounted ?? false) {
      return router.routerDelegate.navigatorKey.currentContext!;
    }
    throw FlutterError('AppRouter [currentContext] cannot be null');
  }

  String get currentRouterName {
    final route = router.routerDelegate.currentConfiguration.last.route;
    return route.name ?? route.path;
  }

  List<INavDestinationModule> get _destinations {
    return getAllOrEmpty<INavDestinationModule>().toList()
      ..sort((a, b) => a.order.compareTo(b.order));
  }

  List<RouteBase> get _featureRoutes {
    return [
      for (final module in getAllOrEmpty<IFeatureRouteModule>())
        ...module.routes,
    ];
  }

  List<StatefulShellBranch> get _dashboardBranches {
    final tabs = _destinations;
    if (tabs.isEmpty) {
      return [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: _emptyDestinationPath,
              builder: (_, _) => const SizedBox.shrink(),
            ),
          ],
        ),
      ];
    }
    return [
      for (final tab in tabs) StatefulShellBranch(routes: tab.routes),
    ];
  }

  /// The placeholder branch registered when no module contributes a
  /// destination, so there is always a real route to land on.
  static const _emptyDestinationPath = '/_empty_dashboard';

  /// The app's home: the first destination, or the placeholder branch when
  /// no module contributes one. Always a registered route.
  ///
  /// Used by [back] when there is nothing to pop, by `UndefineRouteWidget`,
  /// and by `NavigatorWrapperWidget` after sign-in when no
  /// `IPostSignInLocation` is registered, and as the cold-start location once the entry location has
  /// been seen (see [entryLocation]). It is deliberately *not* the entry
  /// location itself: that is onboarding when composed, and sending a
  /// signed-in user back to onboarding — or a "go home" tap there — would be
  /// wrong.
  String get fallbackLocation {
    final tabs = _destinations;
    if (tabs.isNotEmpty) return tabs.first.path;
    return _emptyDestinationPath;
  }

  /// Where a cold start lands: the registered [IAppEntryLocation]
  /// (onboarding, when composed) on the first launch only, else
  /// [fallbackLocation].
  ///
  /// "First launch" is the shell's own [AppBootStorage.viewedOnboard] flag,
  /// which `NavigatorWrapperWidget` sets the first time it keeps the user on
  /// the entry location. This used to return the entry location on every
  /// cold start, so a returning user saw onboarding until the session restore
  /// finished and the boot redirect moved them on.
  String get entryLocation {
    final entry = getItOrNull<IAppEntryLocation>();
    return resolveEntryLocation(
      entryPath: entry?.path,
      entrySeen:
          entry != null &&
          (getItOrNull<AppBootStorage>()?.viewedOnboard.value ?? false),
      fallback: fallbackLocation,
    );
  }

  /// The pure decision behind [entryLocation]: [entryPath] until it has been
  /// seen, [fallback] afterwards or when there is none.
  @visibleForTesting
  static String resolveEntryLocation({
    required String? entryPath,
    required bool entrySeen,
    required String fallback,
  }) {
    if (entryPath == null || entrySeen) return fallback;
    return entryPath;
  }

  /// GoRouter instance compiled modularly from individual feature routes
  late final GoRouter router = GoRouter(
    debugLogDiagnostics: kDebugMode,
    navigatorKey: NavigatorKeys.rootKey,
    // Without this `RouteAwareWidget` subscribed to an observer no navigator
    // reported to, and `didPush`/`didPopNext` never fired.
    observers: [routeObserver],
    // Re-resolves the current location — running any `redirect` on it — when
    // the session changes. No redirect ships today (no top-level one, none on
    // a sample route), so this is the hook for a module that adds a guard to
    // its own `GoRouteData.redirect`. Sign-in / sign-out *navigation* is done
    // by `NavigatorWrapperWidget`, listening to `ISessionState`.
    refreshListenable: getItOrNull<ISessionRefreshListenable>(),
    errorPageBuilder: (context, state) {
      return NoTransitionPage(child: UndefineRouteWidget(state: state));
    },
    initialLocation: entryLocation,
    routes: [
      ShellRoute(
        navigatorKey: NavigatorKeys.appKey,
        parentNavigatorKey: NavigatorKeys.rootKey,
        builder: (context, state, child) =>
            NavigatorWrapperWidget(child: child),
        routes: [
          ..._featureRoutes,
          StatefulShellRoute.indexedStack(
            parentNavigatorKey: NavigatorKeys.appKey,
            branches: _dashboardBranches,
            // Without a dashboard module the destinations still render, just
            // without chrome: `navigationShell` is itself the widget showing
            // the current branch. This used to fall back to an empty
            // `SizedBox`, so an app composing tabs but no dashboard — an
            // admin app with only `settings`, say — opened on a blank screen.
            builder: (context, state, navigationShell) {
              return getItOrNull<IDashboardRouteModule>()?.builder(
                    context,
                    state,
                    navigationShell,
                  ) ??
                  navigationShell;
            },
          ),
        ],
      ),
    ],
  );

  void go(String location, {Object? extra}) {
    router.go(location, extra: extra);
  }

  Future<T?> push<T>(String location, {Object? extra}) {
    return router.push<T>(location, extra: extra);
  }

  Future<T?> replace<T>(String location, {Object? extra}) {
    return router.replace<T>(location, extra: extra);
  }

  bool back() {
    if (router.canPop()) {
      router.pop();
      return true;
    }
    router.go(fallbackLocation);
    return false;
  }
}
