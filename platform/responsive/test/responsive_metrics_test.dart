import 'package:core_responsive/core_responsive.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// A 360x690 artboard shown on a 720x1380 screen: exactly 2x on both axes,
/// so every expected value is checkable by hand.
const _design = Size(360, 690);
const _double = Size(720, 1380);

ResponsiveMetrics _metrics({
  Size screen = _double,
  bool splitScreenMode = false,
  bool minTextAdapt = false,
  FontSizeResolver? fontSizeResolver,
}) {
  return ResponsiveMetrics(
    screenSize: screen,
    designSize: _design,
    splitScreenMode: splitScreenMode,
    minTextAdapt: minTextAdapt,
    fontSizeResolver: fontSizeResolver,
  );
}

void main() {
  group('scale factors', () {
    test('width and height scale independently', () {
      final m = _metrics(screen: const Size(720, 690));

      expect(m.scaleWidth, 2.0);
      expect(m.scaleHeight, 1.0);
    });

    test('splitScreenMode floors the height used for vertical scaling', () {
      // 300 dp tall window: without the floor the vertical scale would be
      // 300/690 ≈ 0.43 and every gap would collapse.
      final clamped = _metrics(
        screen: const Size(720, 300),
        splitScreenMode: true,
      );
      final unclamped = _metrics(screen: const Size(720, 300));

      expect(
        clamped.scaleHeight,
        ResponsiveConstants.SPLIT_SCREEN_MIN_HEIGHT / _design.height,
      );
      expect(unclamped.scaleHeight, 300 / _design.height);
      expect(clamped.scaleHeight, greaterThan(unclamped.scaleHeight));
    });

    test('a tall window is unaffected by splitScreenMode', () {
      final a = _metrics(splitScreenMode: true);
      final b = _metrics();

      expect(a.scaleHeight, b.scaleHeight);
    });
  });

  group('value scaling', () {
    test('width, height and radius each use their own axis', () {
      // Wide and short: the axes disagree, so a wrong axis is visible.
      final m = _metrics(screen: const Size(720, 690));

      expect(m.width(10), 20); // 10 * 2.0
      expect(m.height(10), 10); // 10 * 1.0
      expect(m.radius(10), 10); // 10 * min(2.0, 1.0)
      expect(m.diameter(10), 20); // 10 * max(2.0, 1.0)
      expect(m.diagonal(10), 20); // 10 * 2.0 * 1.0
    });

    test('radius never stretches with a single axis', () {
      final m = _metrics(screen: const Size(1440, 690));

      expect(m.scaleWidth, 4.0);
      expect(m.radius(10), 10); // still the smaller axis
    });
  });

  group('text scaling', () {
    test('defaults to the width scale', () {
      final m = _metrics(screen: const Size(720, 690));

      expect(m.sp(10), 20); // 10 * scaleWidth
    });

    test('minTextAdapt uses the smaller axis so text cannot balloon', () {
      final m = _metrics(screen: const Size(720, 690), minTextAdapt: true);

      expect(m.sp(10), 10); // 10 * min(2.0, 1.0)
    });

    test('fontSizeResolver overrides scaling entirely', () {
      final m = _metrics(fontSizeResolver: (size, _) => size * 3);

      expect(m.sp(10), 30);
    });

    test('the resolver receives the metrics it belongs to', () {
      late ResponsiveMetrics seen;
      final m = _metrics(
        fontSizeResolver: (size, metrics) {
          seen = metrics;
          return size.toDouble();
        },
      );

      m.sp(10);

      expect(seen.screenSize, _double);
      expect(seen.designSize, _design);
    });

    test('spMin caps at the design value — shrinks but never grows', () {
      final big = _metrics(screen: const Size(720, 1380));
      final small = _metrics(screen: const Size(180, 345));

      expect(big.spMin(10), 10); // would be 20, capped
      expect(small.spMin(10), 5); // shrinks freely
    });
  });

  group('equality drives rebuilds', () {
    test('identical inputs compare equal', () {
      expect(_metrics(), _metrics());
      expect(_metrics().hashCode, _metrics().hashCode);
    });

    test('a different screen size compares unequal', () {
      expect(_metrics(), isNot(_metrics(screen: const Size(721, 1380))));
    });

    test('a different flag compares unequal', () {
      expect(_metrics(), isNot(_metrics(minTextAdapt: true)));
    });
  });
}
