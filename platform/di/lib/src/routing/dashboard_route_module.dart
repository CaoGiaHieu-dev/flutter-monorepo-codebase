import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

abstract class DashboardRouteModule {
  Widget builder(
    BuildContext context,
    GoRouterState state,
    StatefulNavigationShell navigationShell,
  );
}
