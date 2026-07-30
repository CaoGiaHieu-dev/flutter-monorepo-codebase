import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Top-level feature routes nested under the app [ShellRoute]
/// (e.g. onboarding, auth) — not dashboard tabs.
///
/// Register via DI; the app shell expands `getAllOrEmpty<IFeatureRouteModule>()`.
/// Sibling route order does not matter when paths are distinct (GoRouter matches
/// by path). Prefer unique paths; avoid overlapping catch-alls across modules.
abstract class IFeatureRouteModule {
  List<RouteBase> get routes;
}

/// Global shared NavigatorKeys to avoid circular dependency between feature packages
/// and the main app shell when defining nested/shell navigators.
class NavigatorKeys {
  NavigatorKeys._();
  static final appKey = GlobalKey<NavigatorState>();
  static final rootKey = GlobalKey<NavigatorState>();
  static final authKey = GlobalKey<NavigatorState>();
  static final homeKey = GlobalKey<NavigatorState>();
}
