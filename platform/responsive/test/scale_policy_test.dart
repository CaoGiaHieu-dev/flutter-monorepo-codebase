import 'package:core_responsive/core_responsive.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// A 400x800 artboard: every window below is a clean multiple of it, so each
/// expected factor is checkable by hand.
const _design = Size(400, 800);

/// Twice the artboard on both axes.
const _double = Size(800, 1600);

/// Half the artboard on both axes.
const _half = Size(200, 400);

/// Metrics against [_design] with everything else configurable.
ResponsiveMetrics _metrics(
  Size screen, {
  Size design = _design,
  ScaleBounds scaleBounds = const ScaleBounds.downOnly(),
  ScaleBounds textScaleBounds = const ScaleBounds.downOnly(),
  Map<WindowSizeClass, ResponsiveProfile> profiles = const {},
  bool minTextAdapt = false,
  FontSizeResolver? fontSizeResolver,
}) {
  return ResponsiveMetrics(
    screenSize: screen,
    designSize: design,
    scaleBounds: scaleBounds,
    textScaleBounds: textScaleBounds,
    profiles: profiles,
    minTextAdapt: minTextAdapt,
    fontSizeResolver: fontSizeResolver,
  );
}

double _tripleFont(num size, ResponsiveMetrics metrics) => size * 3.0;

void main() {
  group('ScaleBounds', () {
    test('clamp leaves a factor inside the range alone', () {
      const bounds = ScaleBounds(min: 0.5, max: 1.5);

      expect(bounds.clamp(0.75), 0.75);
      expect(bounds.clamp(0.5), 0.5);
      expect(bounds.clamp(1.5), 1.5);
    });

    test('clamp pulls a factor outside the range to the nearest end', () {
      const bounds = ScaleBounds(min: 0.5, max: 1.5);

      expect(bounds.clamp(0.25), 0.5);
      expect(bounds.clamp(3.4), 1.5);
    });

    test('the named ranges mean what they say', () {
      expect(const ScaleBounds.unbounded().clamp(0.01), 0.01);
      expect(const ScaleBounds.unbounded().clamp(3.4), 3.4);

      expect(const ScaleBounds.downOnly().clamp(0.5), 0.5);
      expect(const ScaleBounds.downOnly().clamp(3.4), 1.0);

      expect(const ScaleBounds.fixed().clamp(0.5), 1.0);
      expect(const ScaleBounds.fixed().clamp(3.4), 1.0);
    });

    test('rejects a negative min and a min above max', () {
      // Runtime values: a const invocation would fail at compile time instead.
      final negative = -0.5;
      final low = 0.5;

      expect(() => ScaleBounds(min: negative), throwsAssertionError);
      expect(() => ScaleBounds(min: 1.0, max: low), throwsAssertionError);
    });

    test('compares by value', () {
      // Built at runtime: two const expressions with the same fields are
      // canonicalised to one instance and would pass on identity alone.
      final one = 1.0;
      final runtime = ScaleBounds(max: one);

      expect(identical(runtime, const ScaleBounds.downOnly()), isFalse);
      expect(runtime, const ScaleBounds.downOnly());
      expect(runtime.hashCode, const ScaleBounds.downOnly().hashCode);
      expect(const ScaleBounds(max: 1.25), isNot(const ScaleBounds.downOnly()));
      expect(const ScaleBounds(min: 0.5), isNot(const ScaleBounds.unbounded()));
      expect(
        const ScaleBounds(min: 0.5, max: 2).toString(),
        'ScaleBounds(min: 0.5, max: 2.0)',
      );
    });
  });

  group('default policy: scale down, never up', () {
    test('both bounds default to downOnly', () {
      const m = ResponsiveMetrics(screenSize: _double, designSize: _design);

      expect(m.scaleBounds, const ScaleBounds.downOnly());
      expect(m.textScaleBounds, const ScaleBounds.downOnly());
      expect(m.profiles, isEmpty);
    });

    test('a wide desktop window draws a phone design 1:1', () {
      // The reported case: 1280 wide against a 375 artboard is 3.4x
      // unbounded, and an app-bar title rendered huge and clipped.
      const m = ResponsiveMetrics(
        screenSize: Size(1280, 900),
        designSize: Size(375, 812),
      );

      expect(m.scaleWidth, 1.0);
      expect(m.scaleHeight, 1.0);
      expect(m.scaleText, 1.0);
      expect(m.width(20), 20);
      expect(m.sp(20), 20);
    });

    test('a window smaller than the design still shrinks', () {
      const m = ResponsiveMetrics(screenSize: _half, designSize: _design);

      expect(m.scaleWidth, 0.5);
      expect(m.scaleHeight, 0.5);
      expect(m.width(10), 5);
      expect(m.height(10), 5);
      expect(m.radius(10), 5);
      expect(m.sp(10), 5);
    });

    test('each axis is clamped on its own', () {
      // Twice as wide, half as tall: width stops at 1, height shrinks.
      const m = ResponsiveMetrics(
        screenSize: Size(800, 400),
        designSize: _design,
      );

      expect(m.scaleWidth, 1.0);
      expect(m.scaleHeight, 0.5);
      expect(m.radius(10), 5); // smaller axis
      expect(m.diameter(10), 10); // larger axis, already clamped
      expect(m.diagonal(10), 5); // 1.0 * 0.5
    });
  });

  group('opt-in bounds', () {
    test('scale-up is allowed up to max and no further', () {
      const upTo125 = ScaleBounds(max: 1.25);

      final within = _metrics(const Size(450, 900), scaleBounds: upTo125);
      final beyond = _metrics(_double, scaleBounds: upTo125);

      expect(within.scaleWidth, 1.125);
      expect(within.scaleHeight, 1.125);
      expect(beyond.scaleWidth, 1.25);
      expect(beyond.scaleHeight, 1.25);
      expect(beyond.width(20), 25);
    });

    test('min floors how far a design may shrink', () {
      const floor = ScaleBounds(min: 0.75);

      final above = _metrics(const Size(350, 700), scaleBounds: floor);
      final below = _metrics(_half, scaleBounds: floor);

      expect(above.scaleWidth, 0.875);
      expect(below.scaleWidth, 0.75);
      expect(below.scaleHeight, 0.75);
      expect(below.width(20), 15);
    });

    test('text may grow while layout may not', () {
      final m = _metrics(
        _double,
        textScaleBounds: const ScaleBounds(max: 1.5),
      );

      expect(m.width(10), 10); // layout: downOnly
      expect(m.sp(10), 15); // text: from the raw 2x, capped at 1.5
    });

    test('layout may grow while text may not', () {
      final m = _metrics(_double, scaleBounds: const ScaleBounds.unbounded());

      expect(m.width(10), 20);
      expect(m.sp(10), 10);
    });

    test('a text floor leaves layout free to shrink', () {
      final m = _metrics(
        _half,
        textScaleBounds: const ScaleBounds(min: 0.75, max: 1),
      );

      expect(m.width(10), 5);
      expect(m.sp(10), 7.5);
    });

    test('minTextAdapt picks the smaller raw axis before text bounds', () {
      // Wide and short: raw width 2x, raw height 0.5x.
      final m = _metrics(
        const Size(800, 400),
        textScaleBounds: const ScaleBounds.unbounded(),
        minTextAdapt: true,
      );

      expect(m.sp(10), 5);
    });
  });

  group('fontSizeResolver', () {
    test('is not clamped by the text bounds', () {
      final m = _metrics(_half, fontSizeResolver: _tripleFont);

      expect(m.textScaleBounds, const ScaleBounds.downOnly());
      expect(m.sp(10), 30);
    });

    test('spMin still caps it at the design value', () {
      final m = _metrics(_half, fontSizeResolver: _tripleFont);

      expect(m.spMin(10), 10);
    });
  });

  group('spMin', () {
    test('equals sp under the default text bounds', () {
      for (final screen in [_half, _design, _double]) {
        final m = _metrics(screen);
        expect(m.spMin(10), m.sp(10), reason: '$screen');
      }
    });

    test('caps text that the bounds let grow', () {
      final m = _metrics(
        _double,
        textScaleBounds: const ScaleBounds(max: 1.5),
      );

      expect(m.sp(10), 15);
      expect(m.spMin(10), 10);
    });
  });

  group('ResponsiveProfile.resolve', () {
    const compact = ResponsiveProfile(designSize: Size(1, 1));
    const medium = ResponsiveProfile(designSize: Size(2, 2));
    const large = ResponsiveProfile(designSize: Size(3, 3));

    test('takes the exact class when it has a profile', () {
      const profiles = {
        WindowSizeClass.medium: medium,
        WindowSizeClass.large: large,
      };

      expect(
        ResponsiveProfile.resolve(profiles, WindowSizeClass.medium),
        medium,
      );
      expect(ResponsiveProfile.resolve(profiles, WindowSizeClass.large), large);
    });

    test('falls back to the nearest smaller class', () {
      const profiles = {
        WindowSizeClass.compact: compact,
        WindowSizeClass.medium: medium,
      };

      expect(
        ResponsiveProfile.resolve(profiles, WindowSizeClass.expanded),
        medium,
      );
      expect(
        ResponsiveProfile.resolve(profiles, WindowSizeClass.extraLarge),
        medium,
      );
    });

    test('never falls back to a larger class', () {
      const profiles = {WindowSizeClass.large: large};

      expect(
        ResponsiveProfile.resolve(profiles, WindowSizeClass.compact),
        isNull,
      );
      expect(
        ResponsiveProfile.resolve(profiles, WindowSizeClass.expanded),
        isNull,
      );
    });

    test('an empty map resolves to no profile for every class', () {
      for (final windowClass in WindowSizeClass.values) {
        expect(ResponsiveProfile.resolve(const {}, windowClass), isNull);
      }
    });

    test('compares by value', () {
      const a = ResponsiveProfile(
        designSize: Size(600, 960),
        scaleBounds: ScaleBounds(max: 1.25),
        textScaleBounds: ScaleBounds.fixed(),
        minTextAdapt: true,
      );
      // Built at runtime so it cannot be canonicalised into `a`.
      final width = 600.0;
      final same = ResponsiveProfile(
        designSize: Size(width, 960),
        scaleBounds: ScaleBounds(max: width / 480),
        textScaleBounds: const ScaleBounds(min: 1, max: 1),
        minTextAdapt: true,
      );

      expect(identical(a, same), isFalse);
      expect(a, same);
      expect(a.hashCode, same.hashCode);
      expect(a, isNot(const ResponsiveProfile(designSize: Size(600, 960))));
      expect(a, isNot(const ResponsiveProfile(minTextAdapt: false)));
      expect(a.toString(), contains('designSize: Size(600.0, 960.0)'));
      expect(a.toString(), contains('minTextAdapt: true'));
    });
  });

  group('profiles on metrics', () {
    // With the Material 3 breakpoints: 500 is compact, 700 medium, 1000
    // expanded, 1300 large.
    const tablet = ResponsiveProfile(
      designSize: Size(800, 1000),
      scaleBounds: ScaleBounds.unbounded(),
    );
    const profiles = {WindowSizeClass.medium: tablet};

    test('the active profile follows the window class', () {
      expect(
        _metrics(const Size(500, 800), profiles: profiles).activeProfile,
        isNull,
      );
      expect(
        _metrics(const Size(700, 800), profiles: profiles).activeProfile,
        tablet,
      );
      // No expanded profile: falls back to medium.
      expect(
        _metrics(const Size(1000, 800), profiles: profiles).activeProfile,
        tablet,
      );
    });

    test('without an active profile the top-level values apply', () {
      final m = _metrics(const Size(500, 800), profiles: profiles);

      expect(m.effectiveDesignSize, _design);
      expect(m.effectiveScaleBounds, const ScaleBounds.downOnly());
      expect(m.effectiveTextScaleBounds, const ScaleBounds.downOnly());
      expect(m.effectiveMinTextAdapt, isFalse);
    });

    test("the profile's design size drives the factors", () {
      final m = _metrics(const Size(1000, 1000), profiles: profiles);

      expect(m.designSize, _design); // the base artboard is untouched
      expect(m.effectiveDesignSize, const Size(800, 1000));
      expect(m.scaleWidth, 1.25); // 1000 / 800, not 1000 / 400
      expect(m.scaleHeight, 1.0); // 1000 / 1000, not 1000 / 800
    });

    test('a larger profile artboard shrinks under the default bounds', () {
      // 700 wide is 1.75x the base artboard — flattened to 1 by downOnly —
      // but only half the tablet artboard.
      const bigTablet = {
        WindowSizeClass.medium: ResponsiveProfile(designSize: Size(1400, 1600)),
      };
      final m = _metrics(const Size(700, 800), profiles: bigTablet);

      expect(m.scaleWidth, 0.5);
      expect(m.scaleHeight, 0.5);
    });

    test('null profile fields inherit the top-level values', () {
      const sizeOnly = {
        WindowSizeClass.medium: ResponsiveProfile(designSize: Size(350, 700)),
      };
      final m = _metrics(
        const Size(700, 1400),
        profiles: sizeOnly,
        textScaleBounds: const ScaleBounds(max: 1.5),
        minTextAdapt: true,
      );

      expect(m.effectiveScaleBounds, const ScaleBounds.downOnly());
      expect(m.effectiveTextScaleBounds, const ScaleBounds(max: 1.5));
      expect(m.effectiveMinTextAdapt, isTrue);
      expect(m.scaleWidth, 1.0); // raw 2x, top-level downOnly
      expect(m.sp(10), 15); // raw 2x, top-level text cap 1.5
    });

    test('profile bounds override the top-level bounds', () {
      const desktop = {
        WindowSizeClass.expanded: ResponsiveProfile(
          scaleBounds: ScaleBounds(max: 2),
          textScaleBounds: ScaleBounds.fixed(),
        ),
      };
      final m = _metrics(const Size(1200, 2400), profiles: desktop);

      // 1200 is large: falls back to the expanded profile. Raw 3x.
      expect(m.windowSizeClass, WindowSizeClass.large);
      expect(m.scaleWidth, 2.0);
      expect(m.scaleHeight, 2.0);
      expect(m.sp(10), 10);
    });

    test('a profile can turn minTextAdapt on', () {
      const adapt = {
        WindowSizeClass.medium: ResponsiveProfile(minTextAdapt: true),
      };
      // Wide and short: raw width 2x, raw height 0.5x.
      final m = _metrics(
        const Size(800, 400),
        profiles: adapt,
        textScaleBounds: const ScaleBounds.unbounded(),
      );

      expect(m.effectiveMinTextAdapt, isTrue);
      expect(m.sp(10), 5);
    });

    test('a profile can turn minTextAdapt off', () {
      const noAdapt = {
        WindowSizeClass.medium: ResponsiveProfile(minTextAdapt: false),
      };
      final m = _metrics(
        const Size(800, 400),
        profiles: noAdapt,
        textScaleBounds: const ScaleBounds.unbounded(),
        minTextAdapt: true,
      );

      expect(m.effectiveMinTextAdapt, isFalse);
      expect(m.sp(10), 20);
    });
  });

  group('orientation', () {
    test('follows the window shape', () {
      final landscape = _metrics(const Size(800, 400));
      final portrait = _metrics(const Size(400, 800));

      expect(landscape.orientation, Orientation.landscape);
      expect(landscape.isLandscape, isTrue);
      expect(portrait.orientation, Orientation.portrait);
      expect(portrait.isLandscape, isFalse);
    });

    test('a square window is portrait, as in MediaQueryData', () {
      expect(_metrics(const Size(500, 500)).orientation, Orientation.portrait);
      expect(
        const MediaQueryData(size: Size(500, 500)).orientation,
        Orientation.portrait,
      );
    });
  });

  group('equality covers the policy', () {
    const tablet = ResponsiveProfile(designSize: Size(600, 960));
    const desktop = ResponsiveProfile(scaleBounds: ScaleBounds.fixed());

    test('different bounds compare unequal', () {
      expect(
        _metrics(_double),
        isNot(_metrics(_double, scaleBounds: const ScaleBounds.unbounded())),
      );
      expect(
        _metrics(_double),
        isNot(
          _metrics(_double, textScaleBounds: const ScaleBounds.unbounded()),
        ),
      );
    });

    test('different profiles compare unequal', () {
      const one = {WindowSizeClass.medium: tablet};
      const other = {WindowSizeClass.expanded: tablet};

      expect(_metrics(_double), isNot(_metrics(_double, profiles: one)));
      expect(
        _metrics(_double, profiles: one),
        isNot(_metrics(_double, profiles: other)),
      );
      expect(
        _metrics(_double, profiles: one),
        isNot(
          _metrics(
            _double,
            profiles: const {WindowSizeClass.medium: desktop},
          ),
        ),
      );
    });

    test('profile maps compare by content, not identity or order', () {
      const ordered = {
        WindowSizeClass.medium: tablet,
        WindowSizeClass.expanded: desktop,
      };
      const reversed = {
        WindowSizeClass.expanded: desktop,
        WindowSizeClass.medium: tablet,
      };
      final a = _metrics(_double, profiles: ordered);
      final b = _metrics(_double, profiles: reversed);
      final c = _metrics(_double, profiles: Map.of(ordered));

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, c);
      expect(a.hashCode, c.hashCode);
    });

    test('toString names the policy', () {
      final text = _metrics(
        _double,
        profiles: const {WindowSizeClass.medium: tablet},
      ).toString();

      expect(text, contains('scaleBounds: ${const ScaleBounds.downOnly()}'));
      expect(
        text,
        contains('textScaleBounds: ${const ScaleBounds.downOnly()}'),
      );
      expect(text, contains('WindowSizeClass.medium: $tablet'));
    });
  });

  group('ResponsiveInit', () {
    testWidgets('passes every setting through to the metrics', (tester) async {
      const breakpoints = ResponsiveBreakpoints(
        medium: 500,
        expanded: 900,
        large: 1300,
        extraLarge: 1700,
      );
      const profiles = {
        WindowSizeClass.medium: ResponsiveProfile(
          designSize: Size(340, 700),
          scaleBounds: ScaleBounds(max: 3),
        ),
      };
      late BuildContext ctx;

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(850, 700)),
          child: ResponsiveInit(
            designSize: _design,
            splitScreenMode: true,
            minTextAdapt: true,
            fontSizeResolver: _tripleFont,
            breakpoints: breakpoints,
            scaleBounds: const ScaleBounds(max: 1.25),
            textScaleBounds: const ScaleBounds(min: 0.5),
            profiles: profiles,
            child: Builder(
              builder: (context) {
                ctx = context;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      expect(
        ctx.responsive,
        const ResponsiveMetrics(
          screenSize: Size(850, 700),
          designSize: _design,
          splitScreenMode: true,
          minTextAdapt: true,
          fontSizeResolver: _tripleFont,
          breakpoints: breakpoints,
          scaleBounds: ScaleBounds(max: 1.25),
          textScaleBounds: ScaleBounds(min: 0.5),
          profiles: profiles,
        ),
      );
      // 850 is medium only under the custom breakpoints (expanded under
      // Material 3), so the profile applying proves they arrived too.
      expect(ctx.windowSizeClass, WindowSizeClass.medium);
      expect(ctx.responsive.activeProfile, profiles[WindowSizeClass.medium]);
      expect(ctx.w(10), 25); // 850 / 340 = 2.5, under the profile's cap of 3
    });

    testWidgets('defaults to down-only bounds and no profiles', (
      tester,
    ) async {
      late BuildContext ctx;

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(1280, 900)),
          child: ResponsiveInit(
            child: Builder(
              builder: (context) {
                ctx = context;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      expect(ctx.responsive.scaleBounds, const ScaleBounds.downOnly());
      expect(ctx.responsive.textScaleBounds, const ScaleBounds.downOnly());
      expect(ctx.responsive.profiles, isEmpty);
      expect(ctx.w(20), 20);
      expect(ctx.sp(20), 20);
    });

    testWidgets('a change of bounds alone rebuilds the widgets that scale', (
      tester,
    ) async {
      final widths = <double>[];
      // One instance across both pumps: only the scope's notification can
      // rebuild it, so this fails if equality ignores the bounds.
      final probe = Builder(
        builder: (context) {
          widths.add(context.w(10));
          return const SizedBox.shrink();
        },
      );

      Widget app(ScaleBounds bounds) => MediaQuery(
        data: const MediaQueryData(size: _double),
        child: ResponsiveInit(
          designSize: _design,
          scaleBounds: bounds,
          child: probe,
        ),
      );

      await tester.pumpWidget(app(const ScaleBounds.downOnly()));
      await tester.pumpWidget(app(const ScaleBounds.unbounded()));

      expect(widths, [10.0, 20.0]);
    });

    testWidgets('a change of profiles alone rebuilds the widgets that scale', (
      tester,
    ) async {
      final widths = <double>[];
      final probe = Builder(
        builder: (context) {
          widths.add(context.w(10));
          return const SizedBox.shrink();
        },
      );

      Widget app(Map<WindowSizeClass, ResponsiveProfile> profiles) =>
          MediaQuery(
            data: const MediaQueryData(size: _double),
            child: ResponsiveInit(
              designSize: _design,
              profiles: profiles,
              child: probe,
            ),
          );

      await tester.pumpWidget(app(const {}));
      await tester.pumpWidget(
        app(const {
          WindowSizeClass.medium: ResponsiveProfile(
            scaleBounds: ScaleBounds.unbounded(),
          ),
        }),
      );

      expect(widths, [10.0, 20.0]);
    });
  });
}
