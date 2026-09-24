import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:core_responsive/core_responsive.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pumps a probe into a window of [size] and returns the probe's context.
///
/// No `ResponsiveInit` unless [breakpoints] is given: the adaptive helpers
/// must work without one.
Future<BuildContext> _contextAt(
  WidgetTester tester,
  Size size, {
  List<DisplayFeature> displayFeatures = const [],
  ResponsiveBreakpoints? breakpoints,
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1.0
    ..displayFeatures = displayFeatures;
  addTearDown(tester.view.reset);

  late BuildContext captured;
  Widget probe = Builder(
    builder: (context) {
      captured = context;
      return const SizedBox.shrink();
    },
  );
  if (breakpoints != null) {
    probe = ResponsiveInit(breakpoints: breakpoints, child: probe);
  }
  await tester.pumpWidget(probe);
  return captured;
}

/// One width per Material 3 window size class.
const _widths = {
  WindowSizeClass.compact: 390.0,
  WindowSizeClass.medium: 700.0,
  WindowSizeClass.expanded: 900.0,
  WindowSizeClass.large: 1300.0,
  WindowSizeClass.extraLarge: 1700.0,
};

DisplayFeature _feature(
  Rect bounds,
  DisplayFeatureType type, [
  DisplayFeatureState state = DisplayFeatureState.unknown,
]) => DisplayFeature(bounds: bounds, type: type, state: state);

/// A book-style fold down the middle of a 700x800 window.
const _verticalFold = Rect.fromLTWH(350, 0, 0, 800);

/// A flip phone's fold across the middle of a 700x800 window.
const _horizontalFold = Rect.fromLTWH(0, 400, 700, 0);

void main() {
  group('window size class', () {
    testWidgets('is classified from MediaQuery when no ResponsiveInit is '
        'above', (tester) async {
      for (final MapEntry(key: expected, value: width) in _widths.entries) {
        final context = await _contextAt(tester, Size(width, 800));

        expect(context.windowSizeClass, expected, reason: '$width');
      }
    });

    testWidgets('honours the breakpoints of a ResponsiveInit above', (
      tester,
    ) async {
      // 750 is medium under Material 3, expanded under these breakpoints.
      const custom = ResponsiveBreakpoints(
        medium: 500,
        expanded: 700,
        large: 1000,
        extraLarge: 1400,
      );

      final plain = await _contextAt(tester, const Size(750, 800));
      expect(plain.windowSizeClass, WindowSizeClass.medium);

      final scoped = await _contextAt(
        tester,
        const Size(750, 800),
        breakpoints: custom,
      );
      expect(scoped.windowSizeClass, WindowSizeClass.expanded);
    });

    testWidgets('isCompactWindow and isExpandedOrWider', (tester) async {
      final phone = await _contextAt(tester, const Size(390, 800));
      expect(phone.isCompactWindow, isTrue);
      expect(phone.isExpandedOrWider, isFalse);

      final smallTablet = await _contextAt(tester, const Size(700, 800));
      expect(smallTablet.isCompactWindow, isFalse);
      expect(smallTablet.isExpandedOrWider, isFalse);

      final tablet = await _contextAt(tester, const Size(900, 800));
      expect(tablet.isCompactWindow, isFalse);
      expect(tablet.isExpandedOrWider, isTrue);
    });
  });

  group('adaptive()', () {
    testWidgets('a missing class falls back to the nearest smaller one', (
      tester,
    ) async {
      const expected = {
        WindowSizeClass.compact: 'c',
        WindowSizeClass.medium: 'c', // no medium: back to compact
        WindowSizeClass.expanded: 'e',
        WindowSizeClass.large: 'e', // no large: back to expanded
        WindowSizeClass.extraLarge: 'e',
      };

      for (final MapEntry(key: sizeClass, value: width) in _widths.entries) {
        final context = await _contextAt(tester, Size(width, 800));

        expect(
          context.adaptive(compact: 'c', expanded: 'e'),
          expected[sizeClass],
          reason: '$sizeClass',
        );
      }
    });

    testWidgets('fallback skips every gap, not only one', (tester) async {
      final context = await _contextAt(tester, const Size(1700, 800));

      // extraLarge -> large (none) -> expanded (none) -> medium.
      expect(context.adaptive(compact: 1, medium: 2), 2);
    });

    testWidgets('each class takes its own value when given', (tester) async {
      for (final MapEntry(key: sizeClass, value: width) in _widths.entries) {
        final context = await _contextAt(tester, Size(width, 800));

        expect(
          context.adaptive(
            compact: WindowSizeClass.compact,
            medium: WindowSizeClass.medium,
            expanded: WindowSizeClass.expanded,
            large: WindowSizeClass.large,
            extraLarge: WindowSizeClass.extraLarge,
          ),
          sizeClass,
        );
      }
    });
  });

  group('separatingDisplayFeature and foldPosture', () {
    testWidgets('nothing on a plain window: flat', (tester) async {
      final context = await _contextAt(tester, const Size(700, 800));

      expect(context.separatingDisplayFeature, isNull);
      expect(context.foldPosture, FoldPosture.flat);
    });

    testWidgets('a half-opened vertical fold: book', (tester) async {
      final fold = _feature(
        _verticalFold,
        DisplayFeatureType.fold,
        DisplayFeatureState.postureHalfOpened,
      );
      final context = await _contextAt(
        tester,
        const Size(700, 800),
        displayFeatures: [fold],
      );

      expect(context.separatingDisplayFeature, fold);
      expect(context.foldPosture, FoldPosture.book);
    });

    testWidgets('a half-opened horizontal fold: tabletop', (tester) async {
      final fold = _feature(
        _horizontalFold,
        DisplayFeatureType.fold,
        DisplayFeatureState.postureHalfOpened,
      );
      final context = await _contextAt(
        tester,
        const Size(700, 800),
        displayFeatures: [fold],
      );

      expect(context.separatingDisplayFeature, fold);
      expect(context.foldPosture, FoldPosture.tabletop);
    });

    testWidgets('a fold opened flat, or of unknown state, does not separate', (
      tester,
    ) async {
      for (final state in [
        DisplayFeatureState.postureFlat,
        DisplayFeatureState.unknown,
      ]) {
        final context = await _contextAt(
          tester,
          const Size(700, 800),
          displayFeatures: [
            _feature(_verticalFold, DisplayFeatureType.fold, state),
          ],
        );

        expect(context.separatingDisplayFeature, isNull, reason: '$state');
        expect(context.foldPosture, FoldPosture.flat, reason: '$state');
      }
    });

    testWidgets('a hinge always separates, even opened flat', (tester) async {
      final hinge = _feature(
        const Rect.fromLTRB(340, 0, 360, 800),
        DisplayFeatureType.hinge,
        DisplayFeatureState.postureFlat,
      );
      final context = await _contextAt(
        tester,
        const Size(700, 800),
        displayFeatures: [hinge],
      );

      expect(context.separatingDisplayFeature, hinge);
      expect(context.foldPosture, FoldPosture.book);
    });

    testWidgets('a cutout is ignored, and does not hide a hinge after it', (
      tester,
    ) async {
      final cutout = _feature(
        const Rect.fromLTRB(330, 0, 370, 30),
        DisplayFeatureType.cutout,
      );
      final hinge = _feature(
        const Rect.fromLTRB(340, 0, 360, 800),
        DisplayFeatureType.hinge,
      );

      final onlyCutout = await _contextAt(
        tester,
        const Size(700, 800),
        displayFeatures: [cutout],
      );
      expect(onlyCutout.separatingDisplayFeature, isNull);
      expect(onlyCutout.foldPosture, FoldPosture.flat);

      final both = await _contextAt(
        tester,
        const Size(700, 800),
        displayFeatures: [cutout, hinge],
      );
      expect(both.separatingDisplayFeature, hinge);
    });
  });

  group('FoldPosture.of', () {
    test('reads orientation from the feature alone', () {
      expect(FoldPosture.of(null), FoldPosture.flat);
      expect(
        FoldPosture.of(_feature(_verticalFold, DisplayFeatureType.fold)),
        FoldPosture.book,
      );
      expect(
        FoldPosture.of(_feature(_horizontalFold, DisplayFeatureType.fold)),
        FoldPosture.tabletop,
      );
      // A hinge is a strip, not a line: still longer than it is thick.
      expect(
        FoldPosture.of(
          _feature(
            const Rect.fromLTRB(0, 390, 700, 410),
            DisplayFeatureType.hinge,
          ),
        ),
        FoldPosture.tabletop,
      );
    });
  });
}
