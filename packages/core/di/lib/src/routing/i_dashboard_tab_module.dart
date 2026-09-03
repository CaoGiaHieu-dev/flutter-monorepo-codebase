import 'package:dynamic_logger/dynamic_logger.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// One dashboard bottom-nav tab + matching [StatefulShellBranch] routes.
///
/// Features register implementations via DI (same pattern as [IFeatureLocalization]).
/// The app shell and [DashboardRouteModule] collect them with
/// `getAllOrEmpty<IDashboardTabModule>()` sorted by [order].
///
/// Removing a feature package (and its DI module) drops that tab without
/// breaking the host app.
abstract class IDashboardTabModule {
  /// Ascending order for shell branches and bottom-nav items (0 = first).
  int get order;

  /// Canonical path for this tab (e.g. `/home`), used for fallbacks.
  String get path;

  /// Routes mounted inside a single [StatefulShellBranch].
  List<RouteBase> get routes;

  void onRestore() {
    DynamicLogger.log('onRestore $runtimeType', level: LogLevel.INFO);
  }

  BottomNavigationBarItem navigationBarItem(BuildContext context);
}
