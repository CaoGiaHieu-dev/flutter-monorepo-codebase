import 'package:core_common/core_common.dart';
import 'package:core_di/core_di.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../feature_auth.dart';

part 'auth_route_module.g.dart';

/// SAMPLE — a feature contributing top-level routes.
///
/// The shell route gives the auth flow its own nested [Navigator] (its own back
/// stack) via [NavigatorKeys.authKey]. One child route is enough to show the
/// shape; add siblings as `TypedGoRoute` entries here.
@TypedShellRoute<AuthShellRoute>(
  routes: [TypedGoRoute<LoginRoute>(path: AuthPath.LOGIN)],
)
class AuthShellRoute extends ShellRouteData {
  const AuthShellRoute();

  static final $navigatorKey = NavigatorKeys.authKey;
  static final $parentNavigatorKey = NavigatorKeys.appKey;

  @override
  Widget builder(BuildContext context, GoRouterState state, Widget navigator) {
    return navigator;
  }
}

/// Controllers are instantiated at the route, not inside the page — AGENTS §3.1.
/// Here `AuthProvider` is a global `@lazySingleton` mounted by `AuthTreeWrapper`,
/// so this route builds the page directly. A screen-scoped controller would wrap
/// it in `ChangeNotifierProvider(create: (_) => getIt<XProvider>())` instead.
class LoginRoute extends GoRouteDataCustom with $LoginRoute {
  const LoginRoute();
  static final $parentNavigatorKey = NavigatorKeys.authKey;

  @override
  Widget build(BuildContext context, GoRouterState state) => const LoginPage();
}
