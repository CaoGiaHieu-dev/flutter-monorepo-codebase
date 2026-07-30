import 'package:core_common/core_common.dart';
import 'package:core_di/core_di.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({
    super.key,
    required this.navigationShell,
  });

  final StatefulNavigationShell navigationShell;

  void _onTap(BuildContext context, int index, VoidCallback onRestore) {
    if (index == navigationShell.currentIndex) {
      onRestore();
    } else {
      navigationShell.goBranch(
        index,
        initialLocation: index == navigationShell.currentIndex,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final index = navigationShell.currentIndex;
    final tabs = getAllOrEmpty<IDashboardTabModule>().toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: tabs.length < 2
          ? null
          : BottomNavigationBar(
              currentIndex: index.clamp(0, tabs.length - 1),
              onTap: (tabIndex) {
                _onTap(
                  context,
                  tabIndex,
                  tabs[tabIndex].onRestore,
                );
              },
              items: [
                for (final tab in tabs) tab.navigationBarItem(context),
              ],
            ),
    );
  }
}
