import 'package:core_di/core_di.dart';
import 'package:go_router/go_router.dart';
import 'package:injectable/injectable.dart';
import 'package:material_ui/material_ui.dart';

import '../pages/dashboard_page.dart';

@Singleton(as: DashboardRouteModule)
class DashboardRouteModuleImpl implements DashboardRouteModule {
  @override
  Widget builder(
    BuildContext context,
    GoRouterState state,
    StatefulNavigationShell navigationShell,
  ) {
    return DashboardPage(navigationShell: navigationShell);
  }
}
