import 'package:core_common/core_common.dart';
import 'package:core_di/core_di.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:injectable/injectable.dart';
import 'package:material_ui/material_ui.dart';

import '../widgets/navigator_wrapper_widget.dart';
import '../widgets/undefine_route_widget.dart';

/// Dynamic and decentralized application routing manager.
///
/// Assembles GoRouter from DI contributions:
/// - [IFeatureRouteModule] — top-level feature routes (onboarding, auth, …)
/// - [INavDestinationModule] — primary destinations + their shell branches
/// - [DashboardRouteModule] — dashboard chrome (optional)
/// - [IAppEntryLocation] — cold-start path (optional)
///
/// Missing modules fall back to empty routes / a chromeless shell /
/// [fallbackLocation] (the first destination, else `/_empty_dashboard`).
///
/// Every contribution is resolved optionally and this file imports no feature
/// package, so removing any feature leaves routing intact — including
/// [IAuthRefreshListenable], which simply resolves to `null` when no auth
/// feature is present (the router then never refreshes on session changes,
/// which is correct when there are none).
@singleton
class AppRouter {
  final routeObserver = RouteObserver<ModalRoute>();

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
  /// and by `NavigatorWrapperWidget` after sign-in when no `HomeNavigator` is
  /// registered. It is deliberately *not* the cold-start entry point: that is
  /// onboarding when composed, and sending a signed-in user back to
  /// onboarding — or a "go home" tap there — would be wrong.
  String get fallbackLocation {
    final tabs = _destinations;
    if (tabs.isNotEmpty) return tabs.first.path;
    return _emptyDestinationPath;
  }

  /// Where a cold start lands: the registered [IAppEntryLocation]
  /// (onboarding, when composed), else [fallbackLocation].
  String get entryLocation =>
      getItOrNull<IAppEntryLocation>()?.path ?? fallbackLocation;

  /// GoRouter instance compiled modularly from individual feature routes
  late final GoRouter router = GoRouter(
    debugLogDiagnostics: kDebugMode,
    navigatorKey: NavigatorKeys.rootKey,
    refreshListenable: getItOrNull<IAuthRefreshListenable>(),
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
              return getItOrNull<DashboardRouteModule>()?.builder(
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
