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

  /// Switches branch, keeping each branch's own back stack; re-tapping the
  /// current tab returns that branch to its first page instead.
  void _onSelect(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
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
    // This is where a neutral [NavDestination] becomes one app's widget —
    // the same modules feed both forms below, unchanged.
    final destinations = [for (final tab in tabs) tab.destination(context)];

    // A phone keeps the bottom bar (the shell locks phone-sized displays to
    // portrait). From a medium window up — a tablet in either orientation,
    // an unfolded foldable, a desktop window — the tabs move to a side
    // rail, which costs width the window has to spare instead of height it
    // has not.
    final sizeClass = context.windowSizeClass;
    if (sizeClass.isSmallerThan(WindowSizeClass.medium)) {
      return Scaffold(
        body: navigationShell,
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: selected,
          onTap: _onSelect,
          items: [for (final d in destinations) _itemOf(d)],
        ),
      );
    }

    final extended = sizeClass.isAtLeast(WindowSizeClass.large);
    // The rail sits at the start edge: the left in LTR, the right in RTL
    // (a `Row` follows the text direction). It pads for the insets on its
    // outer side only; the side facing the content is the content's to pad.
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    return Scaffold(
      body: Row(
        children: [
          SafeArea(
            left: !isRtl,
            right: isRtl,
            child: NavigationRail(
              selectedIndex: selected,
              onDestinationSelected: _onSelect,
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
