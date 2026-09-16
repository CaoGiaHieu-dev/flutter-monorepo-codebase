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
/// - [IDashboardTabModule] — dashboard shell branches + bottom-nav tabs
/// - [DashboardRouteModule] — dashboard chrome (optional)
/// - [IAppEntryLocation] — cold-start path (optional)
///
/// Missing modules fall back to empty routes / [SizedBox] / `/`.
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

  List<IDashboardTabModule> get _dashboardTabs {
    return getAllOrEmpty<IDashboardTabModule>().toList()
      ..sort((a, b) => a.order.compareTo(b.order));
  }

  List<RouteBase> get _featureRoutes {
    return [
      for (final module in getAllOrEmpty<IFeatureRouteModule>())
        ...module.routes,
    ];
  }

  List<StatefulShellBranch> get _dashboardBranches {
    final tabs = _dashboardTabs;
    if (tabs.isEmpty) {
      return [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/_empty_dashboard',
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

  String get _fallbackLocation {
    final entry = getItOrNull<IAppEntryLocation>()?.path;
    if (entry != null) return entry;
    final tabs = _dashboardTabs;
    if (tabs.isNotEmpty) return tabs.first.path;
    return '/';
  }

  /// GoRouter instance compiled modularly from individual feature routes
  late final GoRouter router = GoRouter(
    debugLogDiagnostics: kDebugMode,
    navigatorKey: NavigatorKeys.rootKey,
    refreshListenable: getItOrNull<IAuthRefreshListenable>(),
    errorPageBuilder: (context, state) {
      return NoTransitionPage(child: UndefineRouteWidget(state: state));
    },
    initialLocation: _fallbackLocation,
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
            builder: (context, state, navigationShell) {
              return getItOrNull<DashboardRouteModule>()?.builder(
                    context,
                    state,
                    navigationShell,
                  ) ??
                  const SizedBox.shrink();
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
    router.go(_fallbackLocation);
    return false;
  }
}
