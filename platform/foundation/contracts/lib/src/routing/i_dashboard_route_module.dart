import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'i_nav_destination_module.dart';

/// Builds the dashboard chrome around the app's [StatefulNavigationShell].
///
/// Optional: the app shell resolves it with `getItOrNull`, so an app
/// composed without the dashboard module still boots.
abstract class IDashboardRouteModule {
  /// [destinations] are the registered [INavDestinationModule]s sorted by
  /// `order`, collected once by the shell's router: destination `i` is
  /// branch `i` of [navigationShell]. Render them rather than collecting
  /// them again.
  Widget builder(
    BuildContext context,
    GoRouterState state,
    StatefulNavigationShell navigationShell,
    List<INavDestinationModule> destinations,
  );
}
