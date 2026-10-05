import 'package:core_responsive/core_responsive.dart';
import 'package:feature_dashboard/feature_dashboard.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_nav_destination.dart';

/// The app honours the OS font size up to 2x (the shell clamps it). The
/// dashboard chrome — bottom bar on a phone, rail from a medium window,
/// extended rail from a large one — must lay out at that cap without an
/// overflow, with every label shown.
const _labels = ['Home', 'Settings', 'Messages', 'Profile'];

void main() {
  final tabs = [
    for (final (i, label) in _labels.indexed)
      FakeNavDestination(i, '/t$i', label),
  ];

  Future<void> pumpDashboard(WidgetTester tester, Size window) async {
    tester.view
      ..physicalSize = window
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final router = GoRouter(
      initialLocation: '/t0',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, shell) =>
              DashboardPage(navigationShell: shell, destinations: tabs),
          branches: [
            for (var i = 0; i < tabs.length; i++)
              StatefulShellBranch(
                routes: [
                  GoRoute(path: '/t$i', builder: (_, _) => const SizedBox()),
                ],
              ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ResponsiveInit(
        designSize: const Size(375, 812),
        splitScreenMode: true,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  final cases = <String, (Size, Type)>{
    'compact phone, bottom bar': (const Size(320, 568), BottomNavigationBar),
    'medium window, rail': (const Size(700, 900), NavigationRail),
    'large window, extended rail': (const Size(1280, 800), NavigationRail),
  };

  for (final MapEntry(key: name, value: (window, chrome)) in cases.entries) {
    testWidgets('$name: lays out at 2x text', (tester) async {
      await pumpDashboard(tester, window);

      expect(find.byType(chrome), findsOneWidget);
      for (final label in _labels) {
        expect(find.text(label), findsWidgets);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
