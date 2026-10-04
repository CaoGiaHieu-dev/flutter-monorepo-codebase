import 'dart:async';

import 'package:core_responsive/core_responsive.dart';
import 'package:core_ui_kit/core_ui_kit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// `BottomTransitionPage` is a `Page` that opens its child as a modal bottom
/// sheet, with rounded top corners from the radius tokens.
void main() {
  late GoRouter router;

  Future<void> pump(
    WidgetTester tester, {
    bool isDismissible = true,
    bool enableDrag = true,
  }) async {
    router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: Text('base')),
          routes: [
            GoRoute(
              path: 'sheet',
              pageBuilder: (_, state) => BottomTransitionPage<void>(
                key: state.pageKey,
                isDismissible: isDismissible,
                enableDrag: enableDrag,
                child: const SizedBox(height: 200, child: Text('sheet body')),
              ),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ResponsiveInit(child: MaterialApp.router(routerConfig: router)),
    );
    await tester.pumpAndSettle();
    unawaited(router.push('/sheet'));
    await tester.pumpAndSettle();
  }

  testWidgets('opens its child as a modal bottom sheet over the page', (
    tester,
  ) async {
    await pump(tester);

    expect(find.text('sheet body'), findsOneWidget);
    expect(find.text('base'), findsOneWidget);
    // Anchored to the bottom of the screen, not a full page.
    final sheet = tester.getRect(find.text('sheet body'));
    final screen = tester.getRect(find.byType(MaterialApp));
    expect(sheet.bottom, lessThanOrEqualTo(screen.bottom));
    expect(sheet.top, greaterThan(screen.top));
    expect(find.byType(BottomSheet), findsOneWidget);
  });

  testWidgets('clips the child to rounded top corners only', (tester) async {
    await pump(tester);

    final clip = tester.widget<ClipRRect>(
      find.ancestor(
        of: find.text('sheet body'),
        matching: find.byType(ClipRRect),
      ),
    );
    final radius = clip.borderRadius as BorderRadius;
    expect(radius.topLeft.x, greaterThan(0));
    expect(radius.topRight, radius.topLeft);
    expect(radius.bottomLeft, Radius.zero);
    expect(radius.bottomRight, Radius.zero);
  });

  testWidgets('a tap on the barrier dismisses a dismissible sheet', (
    tester,
  ) async {
    await pump(tester);

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(find.text('sheet body'), findsNothing);
  });

  testWidgets('a non-dismissible sheet ignores the barrier tap', (
    tester,
  ) async {
    await pump(tester, isDismissible: false, enableDrag: false);

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(find.text('sheet body'), findsOneWidget);
  });
}
