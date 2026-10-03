import 'package:core_common/core_common.dart';
import 'package:core_di/core_di.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:injectable/injectable.dart';
import 'package:material_ui/material_ui.dart';
import 'package:platform_shell_adapters/platform_shell_adapters.dart';

import '../shell_hooks.dart';
import '../widgets/navigator_wrapper_widget.dart';
import '../widgets/undefined_route_widget.dart';

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
///
/// What the app says about it: [RouterProfile] — when the entry location is
/// used and which location is the fallback — and the router hooks of
/// [ShellHooks], read with `getItOrNull<ShellHooks>()` because `runShellApp`
/// registers them before DI (so a build or a test without them just has none).
@singleton
class AppRouter {
  /// Creates the router. [profile] is the app's `RouterProfile` — the
  /// template defaults when none is given.
  AppRouter([this.profile = const RouterProfile()]);

  /// The app's router settings: the entry-location policy and the fallback
  /// location.
  final RouterProfile profile;

  /// Observes every navigator the router builds: attached to the root
  /// navigator through `GoRouter(observers:)`, and go_router forwards the
  /// root observers to each `ShellRoute` and `StatefulShellBranch` navigator
  /// (`notifyRootObserver`, on by default) — so one instance sees the whole
  /// app. `AppInitializer.init` hands it to `RouteAwareWidget`.
  final routeObserver = RouteObserver<ModalRoute<void>>();

  /// Every [INavDestinationModule], sorted by `order` — collected once, when
  /// the router is built. Branch `i` of the dashboard shell is destination
  /// `i`; the dashboard receives this same list through
  /// [IDashboardRouteModule.builder], so the two can never disagree.
  late final List<INavDestinationModule> destinations = List.unmodifiable(
    getAllOrEmpty<INavDestinationModule>().toList()
      ..sort((a, b) => a.order.compareTo(b.order)),
  );

  List<RouteBase> get _featureRoutes {
    return [
      for (final module in getAllOrEmpty<IFeatureRouteModule>())
        ...module.routes,
    ];
  }

  List<StatefulShellBranch> get _dashboardBranches {
    final tabs = destinations;
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

  /// The app's home: [RouterProfile.fallbackPath] when the app names one,
  /// else the first destination, or the placeholder branch when no module
  /// contributes one. A registered route, as long as the app's path is.
  ///
  /// Used by `UndefinedRouteWidget`,
  /// and by `NavigatorWrapperWidget` after sign-in when no
  /// `IPostSignInLocation` is registered, and as the cold-start location once the entry location has
  /// been seen (see [entryLocation]). It is deliberately *not* the entry
  /// location itself: that is onboarding when composed, and sending a
  /// signed-in user back to onboarding — or a "go home" tap there — would be
  /// wrong.
  String get fallbackLocation {
    final path = profile.fallbackPath;
    if (path != null) return path;
    final tabs = destinations;
    if (tabs.isNotEmpty) return tabs.first.path;
    return _emptyDestinationPath;
  }

  /// Where a cold start lands, by the app's [RouterProfile.entry]:
  ///
  /// - [EntryPolicy.firstLaunch] (the default): the registered
  ///   [IAppEntryLocation] (onboarding, when composed) on the first launch
  ///   only, else [fallbackLocation];
  /// - [EntryPolicy.always]: the entry location on every cold start;
  /// - [EntryPolicy.never]: [fallbackLocation], whatever is registered.
  ///
  /// "First launch" is the shell's own [AppBootStorage.viewedOnboard] flag,
  /// which `NavigatorWrapperWidget` sets the first time it keeps the user on
  /// the entry location. This used to return the entry location on every
  /// cold start, so a returning user saw onboarding until the session restore
  /// finished and the boot redirect moved them on.
  String get entryLocation {
    final entry = usesEntryLocation ? getItOrNull<IAppEntryLocation>() : null;
    return resolveEntryLocation(
      entryPath: entry?.path,
      entrySeen:
          entry != null &&
          profile.entry == EntryPolicy.firstLaunch &&
          (getItOrNull<AppBootStorage>()?.viewedOnboard ?? false),
      fallback: fallbackLocation,
    );
  }

  /// Whether the app opens on a registered [IAppEntryLocation] at all —
  /// false under [EntryPolicy.never]. `NavigatorWrapperWidget` asks too, so
  /// the boot redirect and the initial location agree.
  bool get usesEntryLocation => profile.entry != EntryPolicy.never;

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
    // Without the shell's own observer `RouteAwareWidget` subscribed to one no
    // navigator reported to, and `didPush`/`didPopNext` never fired. The
    // app's `ShellHooks.navigatorObservers` come after it, never instead.
    observers: [routeObserver, ..._appObservers],
    // Re-resolves the current location — running any `redirect` on it — when
    // the session changes. The app's `ShellHooks.redirect` is the one
    // app-wide guard; a module adds its own to a route's
    // `GoRouteData.redirect`. Sign-in / sign-out *navigation* is done by
    // `NavigatorWrapperWidget`, listening to `ISessionState`.
    redirect: getItOrNull<ShellHooks>()?.redirect,
    refreshListenable: getItOrNull<ISessionRefreshListenable>(),
    errorPageBuilder: (context, state) {
      return NoTransitionPage(child: UndefinedRouteWidget(state: state));
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
                    destinations,
                  ) ??
                  navigationShell;
            },
          ),
        ],
      ),
    ],
  );

  /// The observers the app's [ShellHooks.navigatorObservers] contributes —
  /// none without the hook, or when `runShellApp` registered no runtime.
  List<NavigatorObserver> get _appObservers {
    final hook = getItOrNull<ShellHooks>()?.navigatorObservers;
    final runtime = getItOrNull<AppRuntime>();
    if (hook == null || runtime == null) return const [];
    return hook(runtime);
  }

  void go(String location, {Object? extra}) {
    router.go(location, extra: extra);
  }
}
