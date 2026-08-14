import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

/// A custom GoRouteData implementation that adds support for route awareness,
/// analytics screen tracking, and standard pop/transition behaviors.
abstract class GoRouteDataCustom extends GoRouteData {
  const GoRouteDataCustom();

  ValueKey? get pageKey => null;

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

/// A widget that is aware of route changes and can log screen views.
class RouteAwareWidget extends StatefulWidget {
  final String name;
  final Widget child;

  /// Global route observer registered at app shell level.
  static RouteObserver<ModalRoute>? observer;

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
  void didPush() {
    // AnalyticsService.logScreenView(screenName: widget.name);
  }

  @override
  void didPopNext() {}

  @override
  Widget build(BuildContext context) => widget.child;
}
