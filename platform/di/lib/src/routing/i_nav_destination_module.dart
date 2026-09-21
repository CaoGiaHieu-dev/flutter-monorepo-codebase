import 'package:dynamic_logger/dynamic_logger.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// How one primary navigation destination wants to be shown.
///
/// Deliberately **not** a [BottomNavigationBarItem]. That type is one app's
/// answer — a phone's bottom bar. A desktop build renders a
/// [NavigationRailDestination], an admin web build a sidebar row, and the
/// module contributing the destination should not have to know which. It
/// describes; the app decides.
final class NavDestination {
  const NavDestination({
    required this.label,
    required this.icon,
    this.selectedIcon,
  });

  /// Already translated by the contributing module — the app never re-resolves
  /// it, so a module keeps its own feature-scoped ARB.
  final String label;

  final IconData icon;

  /// Shown while this destination is the active one. Falls back to [icon].
  final IconData? selectedIcon;
}

/// One primary navigation destination plus the routes behind it.
///
/// Modules register implementations via DI. The app shell collects them with
/// `getAllOrEmpty<INavDestinationModule>()` sorted by [order], so removing a
/// module simply drops its destination.
///
/// Use this only for a **primary** destination that needs its own
/// [StatefulShellBranch] — its own navigation stack, preserved across
/// switches. A login screen, a detail page or a push-opened screen is an
/// ordinary route: register `IFeatureRouteModule` instead.
abstract class INavDestinationModule {
  /// Ascending order among destinations (0 = first).
  int get order;

  /// Canonical path for this destination (e.g. `/home`), used for fallbacks.
  String get path;

  /// Routes mounted inside this destination's own [StatefulShellBranch].
  List<RouteBase> get routes;

  /// Called when the user re-selects the destination they are already on —
  /// the conventional "scroll to top / pop to root" gesture.
  void onRestore() {
    DynamicLogger.log('onRestore $runtimeType', level: LogLevel.INFO);
  }

  /// Context is passed so the label can be translated at build time.
  NavDestination destination(BuildContext context);
}
