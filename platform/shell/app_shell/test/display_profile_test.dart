import 'package:core_common/core_common.dart';
import 'package:core_responsive/core_responsive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:platform_app_shell/platform_app_shell.dart';

import 'support/boot_harness.dart';

/// K6 — what an app says about display (`DisplayProfile`) reaches the tree
/// `MainScope` builds. The default is what the shell always did (the 375 x 812
/// artboard, `expanded` laid out in real pixels, split-screen mode on, every
/// other class shrinking only); an app value changes it.
void main() {
  final harness = BootHarness();
  setUp(harness.setUp);
  tearDown(harness.tearDown);

  /// Runs [display] through `MainScope` in a window of [width] x [height] and
  /// returns what `context.w(100)` and `context.h(100)` come to there.
  Future<({double w, double h})> scaled(
    WidgetTester tester, {
    required double width,
    required double height,
    DisplayProfile? display,
  }) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = Size(width, height);
    addTearDown(tester.view.reset);

    double? w;
    double? h;
    var started = false;
    final scope = display == null
        ? MainScope(
            root: Builder(
              builder: (context) {
                w = context.w(100);
                h = context.h(100);
                return const SizedBox.shrink();
              },
            ),
            initService: () async => started = true,
          )
        : MainScope(
            display: display,
            root: Builder(
              builder: (context) {
                w = context.w(100);
                h = context.h(100);
                return const SizedBox.shrink();
              },
            ),
            initService: () async => started = true,
          );
    await tester.runAsync(scope.run);
    await tester.pump();
    expect(started, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    return (w: w!, h: h!);
  }

  group('the defaults are what the shell always did', () {
    testWidgets('a compact window shrinks the 375 artboard to fit', (
      tester,
    ) async {
      final s = await scaled(tester, width: 300, height: 812);
      expect(s.w, closeTo(100 * 300 / 375, 1e-6));
    });

    testWidgets('a compact window never grows past the artboard', (
      tester,
    ) async {
      final s = await scaled(tester, width: 500, height: 900);
      expect(s.w, 100);
      expect(s.h, 100);
    });

    testWidgets('the expanded class is drawn in real pixels, even when short', (
      tester,
    ) async {
      final s = await scaled(tester, width: 1000, height: 500);
      expect(s.w, 100);
      expect(s.h, 100);
    });

    testWidgets('split-screen mode floors the height ratio', (tester) async {
      // Compact and short: 500 is raised to the 700 floor, so 700 / 812.
      final s = await scaled(tester, width: 400, height: 500);
      expect(s.h, closeTo(100 * 700 / 812, 1e-6));
    });
  });

  group('an app value changes it', () {
    testWidgets('designSize is the artboard the window is measured against', (
      tester,
    ) async {
      final s = await scaled(
        tester,
        width: 300,
        height: 812,
        display: const DisplayProfile(designSize: SizeSpec(300, 812)),
      );
      expect(s.w, 100);
    });

    testWidgets('splitScreenMode off lets a short window shrink the height', (
      tester,
    ) async {
      final s = await scaled(
        tester,
        width: 400,
        height: 500,
        display: const DisplayProfile(splitScreenMode: false),
      );
      expect(s.h, closeTo(100 * 500 / 812, 1e-6));
    });

    testWidgets('a bounded policy lets a class grow, to its cap', (
      tester,
    ) async {
      // 750 dp is the medium class; the template leaves it down-only.
      final grown = await scaled(
        tester,
        width: 750,
        height: 1200,
        display: const DisplayProfile(
          scale: {WindowClass.medium: ScalePolicy.bounded(max: 1.5)},
        ),
      );
      expect(grown.w, 150, reason: '750 / 375 = 2, capped at 1.5');

      final stays = await scaled(tester, width: 750, height: 1200);
      expect(stays.w, 100);
    });

    testWidgets('down-only on the expanded class lets a short window shrink', (
      tester,
    ) async {
      final s = await scaled(
        tester,
        width: 1000,
        height: 500,
        display: const DisplayProfile(
          splitScreenMode: false,
          scale: {WindowClass.expanded: ScalePolicy.downOnly()},
        ),
      );
      expect(s.h, closeTo(100 * 500 / 812, 1e-6));
    });
  });
}
