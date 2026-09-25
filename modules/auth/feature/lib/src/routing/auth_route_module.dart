import 'package:core_common/core_common.dart';
import 'package:core_di/core_di.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../pages/login_page.dart';
import '../utils/auth_path.dart';

part 'auth_route_module.g.dart';

/// SAMPLE — a feature contributing a top-level route.
///
/// The login screen sits on the app navigator, above the dashboard's tabs,
/// so it names [NavigatorKeys.appKey] as its parent. Add sibling screens as
/// further `@TypedGoRoute` classes here and list them in
/// `AuthFeatureRouteModule.routes`.
///
/// Controllers are instantiated at the route, not inside the page — RULE-21.
/// Here `AuthProvider` is a global `@lazySingleton` mounted by
/// `AuthTreeWrapper`, so this route builds the page directly. A screen-scoped
/// controller would wrap it in
/// `ChangeNotifierProvider(create: (_) => getIt<XProvider>())` instead.
@TypedGoRoute<LoginRoute>(path: AuthPath.LOGIN)
class LoginRoute extends GoRouteDataCustom with $LoginRoute {
  const LoginRoute();

  static final $parentNavigatorKey = NavigatorKeys.appKey;

  @override
  Widget build(BuildContext context, GoRouterState state) => const LoginPage();
}
