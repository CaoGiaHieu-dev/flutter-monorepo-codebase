import 'package:core_common/core_common.dart';
import 'package:core_responsive/core_responsive.dart';
import 'package:flutter_test/flutter_test.dart';

/// The app profile's defaults are the behaviour the shell had before an app
/// could say anything. A default that exists in two places — here and in a
/// package that must not depend on the kernel — is kept equal by these tests,
/// so changing one side fails a test on the other.
void main() {
  group('DisplayProfile defaults equal the responsive package\'s', () {
    const display = DisplayProfile();

    test('the artboard is the 375 x 812 phone', () {
      expect(
        display.designSize.width,
        ResponsiveConstants.DEFAULT_DESIGN_WIDTH,
      );
      expect(
        display.designSize.height,
        ResponsiveConstants.DEFAULT_DESIGN_HEIGHT,
      );
    });

    test('a phone is a display narrower than the Material 3 medium class', () {
      expect(
        display.phoneMaxShortestSide,
        ResponsiveConstants.BREAKPOINT_MEDIUM,
      );
    });

    test(
      'split-screen mode is ResponsiveInit\'s opt-in the shell always used',
      () {
        expect(display.splitScreenMode, isTrue);
      },
    );
  });

  group('WindowClass equals core_responsive\'s WindowSizeClass', () {
    test('same names, same order', () {
      expect(
        WindowClass.values.map((c) => c.name),
        WindowSizeClass.values.map((c) => c.name),
      );
    });
  });
}
