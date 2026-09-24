import 'package:core_responsive/core_responsive.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _design = Size(360, 690);

/// An unbounded [ResponsiveInit] around [child].
///
/// These tests check that the context extensions reach the right axis and
/// that the scope rebuilds its dependents, so they lift the bounds: under the
/// down-only default every factor above 1 flattens to 1, and a doubled width
/// would be indistinguishable from an unchanged one. The bounds themselves
/// are covered in `scale_policy_test.dart`.
Widget _init(Widget child, {bool minTextAdapt = false}) => ResponsiveInit(
  designSize: _design,
  minTextAdapt: minTextAdapt,
  scaleBounds: const ScaleBounds.unbounded(),
  textScaleBounds: const ScaleBounds.unbounded(),
  child: Directionality(textDirection: TextDirection.ltr, child: child),
);

/// Pumps [child] under a [ResponsiveInit] at a known surface size.
Future<void> _pumpAt(
  WidgetTester tester,
  Size surface,
  Widget child, {
  bool minTextAdapt = false,
}) async {
  tester.view
    ..physicalSize = surface
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(_init(child, minTextAdapt: minTextAdapt));
}

void main() {
  testWidgets('context extensions scale against the design size', (
    tester,
  ) async {
    late BuildContext ctx;
    await _pumpAt(
      tester,
      const Size(720, 690),
      Builder(
        builder: (context) {
          ctx = context;
          return const SizedBox.shrink();
        },
      ),
    );

    expect(ctx.w(10), 20); // width doubled
    expect(ctx.h(10), 10); // height unchanged
    expect(ctx.r(10), 10); // smaller axis
    expect(ctx.sp(10), 20); // defaults to width scale
  });

  testWidgets('edgeInsets scales each side by its own axis', (tester) async {
    late BuildContext ctx;
    await _pumpAt(
      tester,
      const Size(720, 690),
      Builder(
        builder: (context) {
          ctx = context;
          return const SizedBox.shrink();
        },
      ),
    );

    final insets = ctx.edgeInsets(horizontal: 10, vertical: 10);

    expect(insets.left, 20);
    expect(insets.right, 20);
    expect(insets.top, 10);
    expect(insets.bottom, 10);
  });

  testWidgets('a widget that scales rebuilds when the screen resizes', (
    tester,
  ) async {
    final widths = <double>[];

    Widget probe() => Builder(
      builder: (context) {
        widths.add(context.w(10));
        return const SizedBox.shrink();
      },
    );

    await _pumpAt(tester, const Size(360, 690), probe());
    expect(widths, [10.0]);

    // Resize: the scope publishes new metrics, the dependent rebuilds.
    tester.view.physicalSize = const Size(720, 690);
    await tester.pumpWidget(_init(probe()));

    expect(widths, [10.0, 20.0]);
  });

  testWidgets('a widget that does not scale is left alone', (tester) async {
    var builds = 0;

    final inert = Builder(
      builder: (context) {
        builds++;
        return const SizedBox.shrink();
      },
    );

    await _pumpAt(tester, const Size(360, 690), inert);
    expect(builds, 1);

    // Same subtree instance, new metrics: no dependency was registered, so
    // the element is not rebuilt by the scope.
    tester.view.physicalSize = const Size(720, 690);
    await tester.pump();

    expect(builds, 1);
  });

  testWidgets('reading metrics without ResponsiveInit throws a useful error', (
    tester,
  ) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Builder(
          builder: (context) {
            expect(
              () => context.w(10),
              throwsA(
                isA<AssertionError>().having(
                  (e) => e.toString(),
                  'message',
                  contains('No ResponsiveInit found'),
                ),
              ),
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  });

  testWidgets('maybeOf returns null instead of throwing', (tester) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Builder(
          builder: (context) {
            expect(ResponsiveScope.maybeOf(context), isNull);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  });

  testWidgets('a zero-size window (first frame on Android) scales nothing', (
    tester,
  ) async {
    late BuildContext ctx;
    await _pumpAt(
      tester,
      Size.zero,
      Builder(
        builder: (context) {
          ctx = context;
          return const SizedBox.shrink();
        },
      ),
    );

    // Against the unbounded policy a 0-wide window used to scale every
    // value to 0; it is now read as the artboard itself.
    expect(ctx.w(10), 10);
    expect(ctx.h(10), 10);
    expect(ctx.r(10), 10);
    expect(ctx.sp(10), 10);
  });

  group('ResponsiveInit asserts a usable design size', () {
    for (final design in const [Size.zero, Size(0, 690), Size(360, 0)]) {
      testWidgets('designSize $design', (tester) async {
        await tester.pumpWidget(
          ResponsiveInit(designSize: design, child: const SizedBox.shrink()),
        );
        expect(tester.takeException(), isAssertionError);
      });
    }

    testWidgets('a profile designSize, even for a class not in force', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(360, 690)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        const ResponsiveInit(
          profiles: {
            WindowSizeClass.expanded: ResponsiveProfile(
              designSize: Size(0, 800),
            ),
          },
          child: SizedBox.shrink(),
        ),
      );
      expect(tester.takeException(), isAssertionError);
    });
  });
}
