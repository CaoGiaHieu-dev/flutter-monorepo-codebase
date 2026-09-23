import 'package:core_di/core_di.dart';
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

  @override
  Widget build(BuildContext context) {
    final index = navigationShell.currentIndex;
    final tabs = getAllOrEmpty<INavDestinationModule>().toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: tabs.length < 2
          ? null
          : BottomNavigationBar(
              currentIndex: index.clamp(0, tabs.length - 1),
              onTap: (tabIndex) => _onTap(tabIndex, tabs[tabIndex].onRestore),
              // This is where a neutral [NavDestination] becomes one app's
              // widget. A desktop shell would build NavigationRailDestination
              // from the same modules, unchanged.
              items: [
                for (final tab in tabs)
                  _itemOf(tab.destination(context)),
              ],
            ),
    );
  }
}
