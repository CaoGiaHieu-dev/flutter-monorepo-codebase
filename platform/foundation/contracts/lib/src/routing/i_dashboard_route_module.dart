import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// Builds the dashboard chrome around the app's [StatefulNavigationShell].
///
/// Optional: the app shell resolves it with `getItOrNull`, so an app
/// composed without the dashboard module still boots.
abstract class IDashboardRouteModule {
  Widget builder(
    BuildContext context,
    GoRouterState state,
    StatefulNavigationShell navigationShell,
  );
}
