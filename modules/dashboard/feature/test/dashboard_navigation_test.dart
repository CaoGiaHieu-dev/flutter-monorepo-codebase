import 'package:feature_dashboard/feature_dashboard.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_nav_destination.dart';

/// What the chrome does with a tap: switch tab, keep a tab's own stack, return
/// to its first page on a re-tap, and offer nothing for a single destination.
void main() {
  final tabs = [
    FakeNavDestination(0, '/a', 'Alpha'),
    FakeNavDestination(1, '/b', 'Beta'),
  ];
  late GoRouter router;

  Future<void> pumpDashboard(
    WidgetTester tester, {
    Size window = const Size(375, 812),
    int tabCount = 2,
  }) async {
    tester.view
      ..physicalSize = window
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    router = GoRouter(
      initialLocation: '/a',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, shell) => DashboardPage(
            navigationShell: shell,
            destinations: tabs.take(tabCount).toList(),
          ),
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/a',
                  builder: (_, _) => const Text('page a'),
                  routes: [
                    GoRoute(
                      path: 'detail',
                      builder: (_, _) => const Text('page a detail'),
                    ),
                  ],
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(path: '/b', builder: (_, _) => const Text('page b')),
              ],
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
  }

  String location() => router.routeInformationProvider.value.uri.toString();

  testWidgets('a tab keeps its own stack; re-tapping it returns to its first '
      'page', (tester) async {
    await pumpDashboard(tester);
    expect(find.byType(NavigationRail), findsNothing);

    router.go('/a/detail');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Beta'));
    await tester.pumpAndSettle();
    expect(location(), '/b');

    await tester.tap(find.text('Alpha'));
    await tester.pumpAndSettle();
    expect(location(), '/a/detail');

    await tester.tap(find.text('Alpha'));
    await tester.pumpAndSettle();
    expect(location(), '/a');
  });

  testWidgets('a wide window shows the same tabs as a rail', (tester) async {
    await pumpDashboard(tester, window: const Size(1280, 800));

    expect(find.byType(BottomNavigationBar), findsNothing);
    await tester.tap(find.text('Beta'));
    await tester.pumpAndSettle();
    expect(location(), '/b');
  });

  testWidgets('a single destination has nothing to switch, so no chrome', (
    tester,
  ) async {
    await pumpDashboard(tester, tabCount: 1);

    expect(find.byType(BottomNavigationBar), findsNothing);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.text('page a'), findsOneWidget);
  });
}
