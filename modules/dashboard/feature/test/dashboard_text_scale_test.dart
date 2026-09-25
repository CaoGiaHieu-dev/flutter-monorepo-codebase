import 'package:core_responsive/core_responsive.dart';
import 'package:feature_dashboard/feature_dashboard.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_nav_destination.dart';

/// The app honours the OS font size up to 2x (`RootApp` clamps it with
/// `MediaQuery.withClampedTextScaling`). The dashboard chrome — bottom bar
/// on a phone, rail from a medium window, extended rail from a large one —
/// must lay out at that cap without an overflow.
const _maxTextScale = 2.0;

const _tabs = {'/home': 'Home', '/settings': 'Settings', '/inbox': 'Messages'};

void main() {
  var order = 0;
  final tabs = [
    for (final MapEntry(key: path, value: label) in _tabs.entries)
      FakeNavDestination(order += 10, path, label: label),
  ];

  Future<void> pumpDashboard(WidgetTester tester, Size window) async {
    tester.view
      ..physicalSize = window
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = _maxTextScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final router = GoRouter(
      initialLocation: _tabs.keys.first,
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, shell) =>
              DashboardPage(navigationShell: shell, destinations: tabs),
          branches: [
            for (final path in _tabs.keys)
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: path,
                    builder: (_, _) => const SizedBox.shrink(),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      // The app's artboard and default bounds — see `MainScope`.
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
    'phone, bottom bar': (const Size(375, 812), BottomNavigationBar),
    'medium window, rail': (const Size(700, 900), NavigationRail),
    'large window, extended rail': (const Size(1280, 800), NavigationRail),
  };

  for (final MapEntry(key: name, value: (window, chrome)) in cases.entries) {
    testWidgets('$name: lays out at ${_maxTextScale}x text', (tester) async {
      await pumpDashboard(tester, window);

      expect(find.byType(chrome), findsOneWidget);
      for (final label in _tabs.values) {
        expect(find.text(label), findsWidgets);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
