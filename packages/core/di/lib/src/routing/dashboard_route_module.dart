import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

abstract class DashboardRouteModule {
  Widget builder(
    BuildContext context,
    GoRouterState state,
    StatefulNavigationShell navigationShell,
  );
}
