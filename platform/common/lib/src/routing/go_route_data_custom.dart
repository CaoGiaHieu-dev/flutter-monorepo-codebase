import 'dart:async';
import 'dart:io';

import 'package:core_di/core_di.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:platform_kernel/platform_kernel.dart';

/// A custom GoRouteData implementation that adds support for route awareness,
/// analytics screen tracking, and standard pop/transition behaviors.
abstract class GoRouteDataCustom extends GoRouteData {
  const GoRouteDataCustom();

  ValueKey<Object?>? get pageKey => null;

  bool get canPop => true;

  @override
  Widget build(BuildContext context, GoRouterState state) {
    return const SizedBox.shrink();
  }

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    if (kIsWeb) return super.buildPage(context, state);

    final child = RouteAwareWidget(
      state.name ?? state.path ?? 'RouteAwareWidget',
      child: build(context, state),
    );

    if (Platform.isIOS) {
      return CupertinoPage(
        canPop: canPop,
        allowSnapshotting: false,
        key: pageKey ?? state.pageKey,
        child: child,
      );
    }
    return CustomTransitionPage(
      key: pageKey ?? state.pageKey,
      child: child,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return PopScope(
          canPop: canPop,
          child: CupertinoPageTransition(
            key: pageKey ?? state.pageKey,
            linearTransition: true,
            primaryRouteAnimation: animation,
            secondaryRouteAnimation: secondaryAnimation,
            child: child,
          ),
        );
      },
    );
  }
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
