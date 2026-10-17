import 'package:core_di/core_di.dart';
import 'package:core_responsive/core_responsive.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// SAMPLE: navigation chrome only. It turns the neutral [NavDestination]s each
/// tab contributes into a bottom bar on a compact window, or a side rail from
/// a medium one up; the tabs themselves never know which one is showing.
class DashboardPage extends StatelessWidget {
  const DashboardPage({
    super.key,
    required this.navigationShell,
    required this.destinations,
  });

  final StatefulNavigationShell navigationShell;

  /// The primary destinations in branch order, as the shell's router
  /// collected them — see `IDashboardRouteModule.builder`.
  final List<INavDestinationModule> destinations;

  /// Switches branch, keeping each branch's own back stack; re-tapping the
  /// current tab returns that branch to its first page instead.
  void _onSelect(int index) => navigationShell.goBranch(
    index,
    initialLocation: index == navigationShell.currentIndex,
  );

  @override
  Widget build(BuildContext context) {
    // A bar or rail needs at least two destinations.
    if (destinations.length < 2) return Scaffold(body: navigationShell);

    final items = [for (final tab in destinations) tab.destination(context)];
    final selected = navigationShell.currentIndex;
    final sizeClass = context.windowSizeClass;

    if (sizeClass.isSmallerThan(WindowSizeClass.medium)) {
      return Scaffold(
        body: navigationShell,
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: selected,
          onTap: _onSelect,
          // `shifting` (Flutter's default from the fourth tab) hides the
          // labels of unselected tabs.
          type: BottomNavigationBarType.fixed,
          showUnselectedLabels: true,
          items: [
            for (final d in items)
              BottomNavigationBarItem(
                icon: Icon(d.icon),
                activeIcon: Icon(d.selectedIcon ?? d.icon),
                label: d.label,
              ),
          ],
        ),
      );
    }

    // The rail costs width a wide window has to spare, not height it has not.
    final extended = sizeClass.isAtLeast(WindowSizeClass.large);
    return Scaffold(
      body: SafeArea(
        top: false,
        bottom: false,
        child: Row(
          children: [
            NavigationRail(
              selectedIndex: selected,
              onDestinationSelected: _onSelect,
              extended: extended,
              labelType: extended
                  ? NavigationRailLabelType.none
                  : NavigationRailLabelType.all,
              destinations: [
                for (final d in items)
                  NavigationRailDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selectedIcon ?? d.icon),
                    label: Text(d.label),
                  ),
              ],
            ),
            Expanded(child: navigationShell),
          ],
        ),
      ),
    );
  }
}
