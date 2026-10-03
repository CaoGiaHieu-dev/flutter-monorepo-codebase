import 'package:platform_kernel/platform_kernel.dart';
import 'package:test/test.dart';

import 'support/profile_fixtures.dart';

/// Built at run time, so a violated `assert` is an [AssertionError] here and
/// a `const_eval_throws_exception` where an app writes the same value `const`.
DisplayProfile _display({
  double textScaleMax = 2.0,
  SizeSpec designSize = const SizeSpec(375, 812),
  double phoneMaxShortestSide = 600,
}) => DisplayProfile(
  textScaleMax: textScaleMax,
  designSize: designSize,
  phoneMaxShortestSide: phoneMaxShortestSide,
);

SizeSpec _size(double width, double height) => SizeSpec(width, height);

void main() {
  group('DisplayProfile defaults are what the shell did before', () {
    const display = DisplayProfile();

    test('the 375 x 812 phone artboard', () {
      expect(display.designSize.width, 375);
      expect(display.designSize.height, 812);
    });

    test('the OS font size is capped at 200 %', () {
      expect(display.textScaleMax, 2.0);
    });

    test('split-screen mode is on', () {
      expect(display.splitScreenMode, isTrue);
    });

    test('only the expanded class is fixed; the rest stay down-only', () {
      expect(display.scale.keys, [WindowClass.expanded]);
      expect(display.scale[WindowClass.expanded], isA<FixedScale>());
      expect(display.scale[WindowClass.compact], isNull);
    });

    test('a phone is a display whose shortest side is under 600', () {
      expect(display.phoneMaxShortestSide, 600);
    });
  });

  group('DisplayProfile refuses what it cannot honour', () {
    test('a text cap below 200 % is refused (RULE-38)', () {
      expect(() => _display(textScaleMax: 1.5), throwsA(isA<AssertionError>()));
      expect(
        () => _display(textScaleMax: 1.99),
        throwsA(isA<AssertionError>()),
      );
    });

    test('a text cap from 200 % to 400 % is accepted', () {
      expect(_display(textScaleMax: 2.0).textScaleMax, 2.0);
      expect(_display(textScaleMax: 3.0).textScaleMax, 3.0);
      expect(_display(textScaleMax: 4.0).textScaleMax, 4.0);
      expect(() => _display(textScaleMax: 4.5), throwsA(isA<AssertionError>()));
    });

    test('an artboard with no area is refused', () {
      expect(() => _size(0, 812), throwsA(isA<AssertionError>()));
      expect(() => _size(375, -1), throwsA(isA<AssertionError>()));
      expect(_size(375, 812).width, 375);
    });

    test('the phone threshold stays between 300 and 1200', () {
      expect(
        () => _display(phoneMaxShortestSide: 299),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => _display(phoneMaxShortestSide: 1201),
        throwsA(isA<AssertionError>()),
      );
      expect(_display(phoneMaxShortestSide: 720).phoneMaxShortestSide, 720);
    });
  });

  group('ScalePolicy', () {
    test('has three shapes', () {
      expect(const ScalePolicy.fixed(), isA<FixedScale>());
      expect(const ScalePolicy.downOnly(), isA<DownOnlyScale>());
      const bounded = ScalePolicy.bounded(max: 1.2, textMax: 1.1);
      expect(bounded, isA<BoundedScale>());
      expect((bounded as BoundedScale).max, 1.2);
      expect(bounded.textMax, 1.1);
    });

    test('bounded refuses a non-positive factor', () {
      expect(
        () => BoundedScale(max: double.parse('0')),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => BoundedScale(textMax: double.parse('-1')),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('AppProfile carries the sections', () {
    test('left out, they are the defaults', () {
      final profile = mobileProfile();
      expect(profile.display.textScaleMax, const DisplayProfile().textScaleMax);
      expect(profile.router.entry, EntryPolicy.firstLaunch);
      expect(profile.router.fallbackPath, isNull);
    });

    test('given, they are kept', () {
      final profile = AppProfile(
        facts: mobileFacts(),
        display: const DisplayProfile(textScaleMax: 3.0),
        router: const RouterProfile(
          entry: EntryPolicy.never,
          fallbackPath: '/dashboard',
        ),
      );
      expect(profile.display.textScaleMax, 3.0);
      expect(profile.router.entry, EntryPolicy.never);
      expect(profile.router.fallbackPath, '/dashboard');
    });
  });

  group('WindowClass', () {
    test('lists the five Material 3 width classes, narrowest first', () {
      expect(
        WindowClass.values.map((c) => c.name),
        ['compact', 'medium', 'expanded', 'large', 'extraLarge'],
      );
    });
  });
}
