import 'package:core_di/core_di.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// A primary destination with no routes of its own — the dashboard tests
/// hand a list of these to `DashboardPage` in place of real feature modules.
class FakeNavDestination extends INavDestinationModule {
  FakeNavDestination(this.order, this.path, {String? label})
    : label = label ?? 'Tab $order';

  @override
  final int order;

  @override
  final String path;

  final String label;

  @override
  List<RouteBase> get routes => const [];

  @override
  NavDestination destination(BuildContext context) => NavDestination(
    label: label,
    icon: Icons.circle_outlined,
    selectedIcon: Icons.circle,
  );
}
