import 'package:core_di/core_di.dart';
import 'package:feature_dashboard/feature_dashboard.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_nav_destination.dart';

/// What the dashboard chrome does with a tap, as opposed to how it lays out
/// (the other two files): switching tabs, keeping a tab's own stack, and
/// offering no chrome when there is nothing to switch between.
void main() {
  const phone = Size(375, 812);
  const desktop = Size(1280, 800);

  final tabs = [
    FakeNavDestination(0, '/a', label: 'Alpha'),
    FakeNavDestination(1, '/b', label: 'Beta'),
  ];

  late GoRouter router;

  Future<void> pumpDashboard(
    WidgetTester tester, {
    Size window = phone,
    List<INavDestinationModule>? destinations,
  }) async {
    tester.view
      ..physicalSize = window
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final shown = destinations ?? tabs;
    router = GoRouter(
      initialLocation: '/a',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, shell) => DashboardPage(
            navigationShell: shell,
            destinations: shown,
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

  testWidgets('a phone gets a bottom bar with one item per destination', (
    tester,
  ) async {
    await pumpDashboard(tester);

    final bar = tester.widget<BottomNavigationBar>(
      find.byType(BottomNavigationBar),
    );
    expect(bar.items.map((i) => i.label), ['Alpha', 'Beta']);
    expect(bar.currentIndex, 0);
    expect(find.byType(NavigationRail), findsNothing);
  });

  testWidgets('tapping another tab switches branch and marks it selected', (
    tester,
  ) async {
    await pumpDashboard(tester);

    await tester.tap(find.text('Beta'));
    await tester.pumpAndSettle();

    expect(location(), '/b');
    expect(
      tester
          .widget<BottomNavigationBar>(find.byType(BottomNavigationBar))
          .currentIndex,
      1,
    );
  });

  testWidgets('a tab keeps its own stack when you leave and come back', (
    tester,
  ) async {
    await pumpDashboard(tester);
    router.go('/a/detail');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Beta'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alpha'));
    await tester.pumpAndSettle();

    expect(location(), '/a/detail');
  });

  testWidgets('re-tapping the current tab returns it to its first page', (
    tester,
  ) async {
    await pumpDashboard(tester);
    router.go('/a/detail');
    await tester.pumpAndSettle();
    expect(find.text('page a detail'), findsOneWidget);

    await tester.tap(find.text('Alpha'));
    await tester.pumpAndSettle();

    expect(location(), '/a');
    expect(find.text('page a'), findsOneWidget);
  });

  testWidgets('a wide window moves the same tabs to an extended rail', (
    tester,
  ) async {
    await pumpDashboard(tester, window: desktop);

    final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    expect(rail.extended, isTrue);
    expect(rail.destinations, hasLength(2));
    expect(find.byType(BottomNavigationBar), findsNothing);

    await tester.tap(find.text('Beta'));
    await tester.pumpAndSettle();

    expect(location(), '/b');
    expect(
      tester.widget<NavigationRail>(find.byType(NavigationRail)).selectedIndex,
      1,
    );
  });

  testWidgets('a single destination has nothing to switch, so no chrome', (
    tester,
  ) async {
    await pumpDashboard(tester, destinations: [tabs.first]);

    expect(find.byType(BottomNavigationBar), findsNothing);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.text('page a'), findsOneWidget);
  });

  testWidgets('DashboardRouteModuleImpl builds the dashboard page', (
    tester,
  ) async {
    late final Widget built;
    final router = GoRouter(
      initialLocation: '/a',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, shell) {
            built = DashboardRouteModuleImpl().builder(
              context,
              state,
              shell,
              tabs,
            );
            return built;
          },
          branches: [
            StatefulShellBranch(
              routes: [GoRoute(path: '/a', builder: (_, _) => const Text('a'))],
            ),
            StatefulShellBranch(
              routes: [GoRoute(path: '/b', builder: (_, _) => const Text('b'))],
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(built, isA<DashboardPage>());
    expect((built as DashboardPage).destinations, tabs);
  });
}
