import 'package:core_common/core_common.dart';
import 'package:core_di/core_di.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../pages/login_page.dart';
import '../utils/auth_path.dart';

part 'auth_route_module.g.dart';

/// SAMPLE — a feature contributing a top-level route, on the app navigator
/// above the dashboard's tabs. List further routes in
/// `AuthFeatureRouteModule.routes`.
///
/// Controllers are created at the route, not in the page (RULE-21). Here
/// `AuthProvider` is a global `@lazySingleton` mounted by `AuthTreeWrapper`, so
/// the route builds the page directly; a screen-scoped controller would wrap it
/// in `ChangeNotifierProvider(create: (_) => getIt<XProvider>())`.
@TypedGoRoute<LoginRoute>(path: AuthPath.LOGIN)
class LoginRoute extends GoRouteDataCustom with $LoginRoute {
  const LoginRoute();

  static final $parentNavigatorKey = NavigatorKeys.appKey;

  @override
  Widget build(BuildContext context, GoRouterState state) => const LoginPage();
}
