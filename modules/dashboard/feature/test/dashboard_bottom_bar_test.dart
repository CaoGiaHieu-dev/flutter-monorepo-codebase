import 'package:feature_dashboard/feature_dashboard.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_nav_destination.dart';

/// A fourth tab is a one-line change for a template user (the generator's
/// "nav tab" mode); the bar must not change its style because of it.
void main() {
  Future<void> pumpBar(WidgetTester tester, int tabCount) async {
    tester.view
      ..physicalSize = const Size(375, 812)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final tabs = [
      for (var i = 0; i < tabCount; i++)
        FakeNavDestination(i, '/t$i', label: 'Label $i'),
    ];
    final router = GoRouter(
      initialLocation: '/t0',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, shell) =>
              DashboardPage(navigationShell: shell, destinations: tabs),
          branches: [
            for (var i = 0; i < tabCount; i++)
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: '/t$i',
                    builder: (_, _) => const SizedBox.shrink(),
                  ),
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

  for (final count in [3, 4, 5]) {
    testWidgets('$count tabs: every label stays visible', (tester) async {
      await pumpBar(tester, count);

      for (var i = 0; i < count; i++) {
        final label = find.text('Label $i');
        expect(label, findsOneWidget);
        // The unselected labels of a `shifting` bar are faded out.
        for (final fade in tester.widgetList<FadeTransition>(
          find.ancestor(of: label, matching: find.byType(FadeTransition)),
        )) {
          expect(fade.opacity.value, 1.0, reason: 'label $i of $count');
        }
      }
    });
  }
}
