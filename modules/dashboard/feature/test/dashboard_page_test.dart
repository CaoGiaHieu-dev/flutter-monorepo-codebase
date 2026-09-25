import 'package:feature_dashboard/feature_dashboard.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_nav_destination.dart';

/// The side rail must pad for the system insets on its outer edge only —
/// which is the left in LTR and the right in RTL, where a `Row` puts it.
void main() {
  final tabs = [FakeNavDestination(0, '/a'), FakeNavDestination(1, '/b')];

  Future<SafeArea> pumpRail(
    WidgetTester tester,
    TextDirection direction,
  ) async {
    tester.view
      ..physicalSize = const Size(1000, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      initialLocation: '/a',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, shell) =>
              DashboardPage(navigationShell: shell, destinations: tabs),
          branches: [
            for (final path in ['/a', '/b'])
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
      MaterialApp.router(
        routerConfig: router,
        builder: (context, child) =>
            Directionality(textDirection: direction, child: child!),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsOneWidget);
    return tester.widget<SafeArea>(
      find.ancestor(
        of: find.byType(NavigationRail),
        matching: find.byType(SafeArea),
      ),
    );
  }

  testWidgets('LTR: the rail pads its left edge, not the content side', (
    tester,
  ) async {
    final safeArea = await pumpRail(tester, TextDirection.ltr);
    expect(safeArea.left, isTrue);
    expect(safeArea.right, isFalse);
  });

  testWidgets('RTL: the rail pads its right edge, not the content side', (
    tester,
  ) async {
    final safeArea = await pumpRail(tester, TextDirection.rtl);
    expect(safeArea.left, isFalse);
    expect(safeArea.right, isTrue);
  });
}
