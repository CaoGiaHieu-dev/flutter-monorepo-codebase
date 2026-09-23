import 'package:core_di/core_di.dart';
import 'package:core_responsive/core_responsive.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:platform_kernel/platform_kernel.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({
    super.key,
    required this.navigationShell,
  });

  final StatefulNavigationShell navigationShell;

  /// Re-tapping the current tab lets that tab reset itself; any other tap
  /// switches branch, keeping each branch's own back stack.
  void _onTap(int index, VoidCallback onRestore) {
    if (index == navigationShell.currentIndex) {
      onRestore();
    } else {
      navigationShell.goBranch(index);
    }
  }

  BottomNavigationBarItem _itemOf(NavDestination d) {
    return BottomNavigationBarItem(
      icon: Icon(d.icon),
      activeIcon: Icon(d.selectedIcon ?? d.icon),
      label: d.label,
    );
  }

  NavigationRailDestination _railItemOf(NavDestination d) {
    return NavigationRailDestination(
      icon: Icon(d.icon),
      selectedIcon: Icon(d.selectedIcon ?? d.icon),
      label: Text(d.label),
    );
  }

  @override
  Widget build(BuildContext context) {
    final index = navigationShell.currentIndex;
    final tabs = getAllOrEmpty<INavDestinationModule>().toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    if (tabs.length < 2) return Scaffold(body: navigationShell);

    final selected = index.clamp(0, tabs.length - 1);
    void onSelect(int tabIndex) => _onTap(tabIndex, tabs[tabIndex].onRestore);
    // This is where a neutral [NavDestination] becomes one app's widget —
    // the same modules feed both forms below, unchanged.
    final destinations = [for (final tab in tabs) tab.destination(context)];

    // A phone keeps the bottom bar. From a medium window up — a tablet, an
    // unfolded foldable, a desktop — the tabs move to a side rail, which
    // costs width the window has to spare instead of height it has not.
    final sizeClass = context.windowSizeClass;
    if (sizeClass.isSmallerThan(WindowSizeClass.medium)) {
      return Scaffold(
        body: navigationShell,
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: selected,
          onTap: onSelect,
          items: [for (final d in destinations) _itemOf(d)],
        ),
      );
    }

    final extended = sizeClass.isAtLeast(WindowSizeClass.large);
    return Scaffold(
      body: Row(
        children: [
          SafeArea(
            right: false,
            child: NavigationRail(
              selectedIndex: selected,
              onDestinationSelected: onSelect,
              extended: extended,
              labelType: extended
                  ? NavigationRailLabelType.none
                  : NavigationRailLabelType.all,
              destinations: [for (final d in destinations) _railItemOf(d)],
            ),
          ),
          Expanded(child: navigationShell),
        ],
      ),
    );
  }
}
