import 'dart:async';

import 'package:core_di/core_di.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:platform_kernel/platform_kernel.dart';

/// A custom GoRouteData implementation that adds support for route awareness,
/// analytics screen tracking, and standard pop/transition behaviors.
///
/// Every page is wrapped in a [RouteAwareWidget] on every platform, so each
/// screen is reported to the optional `IAnalytics` whether the app runs on a
/// device or on the web.
abstract class GoRouteDataCustom extends GoRouteData {
  const GoRouteDataCustom();

  /// Overrides the key of the page; `null` uses `state.pageKey`.
  ///
  /// Return a stable key to make go_router treat two locations as the same
  /// page (the page is updated in place instead of replaced).
  ValueKey<Object?>? get pageKey => null;

  /// Whether the route may be popped by the system back gesture or button.
  ///
  /// Return `false` for a screen that must not be dismissed that way (a
  /// blocking step); the default is `true`.
  bool get canPop => true;

  @override
  Widget build(BuildContext context, GoRouterState state) {
    return const SizedBox.shrink();
  }

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return routePageFor(
      state: state,
      child: build(context, state),
      canPop: canPop,
      pageKey: pageKey,
      isWeb: kIsWeb,
    );
  }
}

/// Builds the page a [GoRouteDataCustom] route shows.
///
/// [child] is wrapped in a [RouteAwareWidget] named after the route. The page
/// type follows the platform convention: a [CupertinoPage] on iOS, a plain
/// [MaterialPage] on the web (the browser owns the transition), and a
/// Cupertino-style slide everywhere else. [canPop] and [pageKey] apply on all
/// of them. [isWeb] is a parameter so the web branch can be tested; callers
/// pass [kIsWeb].
@visibleForTesting
Page<void> routePageFor({
  required GoRouterState state,
  required Widget child,
  required bool canPop,
  required bool isWeb,
  ValueKey<Object?>? pageKey,
}) {
  final key = pageKey ?? state.pageKey;
  final aware = RouteAwareWidget(
    state.name ?? state.path ?? 'RouteAwareWidget',
    child: child,
  );

  if (isWeb) {
    return MaterialPage<void>(key: key, canPop: canPop, child: aware);
  }
  if (defaultTargetPlatform == TargetPlatform.iOS) {
    return CupertinoPage<void>(
      canPop: canPop,
      allowSnapshotting: false,
      key: key,
      child: aware,
    );
  }
  return CustomTransitionPage<void>(
    key: key,
    child: aware,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return PopScope(
        canPop: canPop,
        child: CupertinoPageTransition(
          key: key,
          linearTransition: true,
          primaryRouteAnimation: animation,
          secondaryRouteAnimation: secondaryAnimation,
          child: child,
        ),
      );
    },
  );
}

/// A widget that is aware of route changes and logs screen views.
///
/// Each time its route becomes the visible one — pushed, or uncovered by
/// the route above it popping — it reports [name] to the optional
/// [IAnalytics] (`getItOrNull`, so an app without analytics registers
/// nothing and nothing is sent). It needs [observer] to hear about either:
/// `AppInitializer.init` sets it to the shell's `AppRouter.routeObserver`.
class RouteAwareWidget extends StatefulWidget {
  final String name;
  final Widget child;

  /// Global route observer registered at app shell level.
  static RouteObserver<ModalRoute<void>>? observer;

  const RouteAwareWidget(this.name, {super.key, required this.child});

  @override
  State<RouteAwareWidget> createState() => RouteAwareWidgetState();
}

class RouteAwareWidgetState extends State<RouteAwareWidget> with RouteAware {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final modalRoute = ModalRoute.of(context);
    if (modalRoute != null) {
      RouteAwareWidget.observer?.subscribe(this, modalRoute);
    }
  }

  @override
  void dispose() {
    RouteAwareWidget.observer?.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPush() => _logScreenView();

  @override
  void didPopNext() => _logScreenView();

  void _logScreenView() {
    final analytics = getItOrNull<IAnalytics>();
    if (analytics == null) return;
    unawaited(analytics.setCurrentScreen(widget.name));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
