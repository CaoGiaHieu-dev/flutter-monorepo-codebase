import 'package:core_common/core_common.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Portrait is locked on phone-sized displays only; tablets, foldables and
/// desktops keep every orientation so they are never letterboxed.
void main() {
  group('AppInitializer.preferredOrientationsFor', () {
    test('locks a phone-sized display to portrait', () {
      for (final side in [320.0, 375.0, 412.0, 599.9]) {
        expect(
          AppInitializer.preferredOrientationsFor(side),
          [DeviceOrientation.portraitUp],
          reason: 'shortest side $side',
        );
      }
    });

    test('leaves a tablet-sized display unlocked', () {
      for (final side in [600.0, 768.0, 1024.0]) {
        expect(
          AppInitializer.preferredOrientationsFor(side),
          isEmpty,
          reason: 'shortest side $side',
        );
      }
    });

    test('leaves an unmeasured display unlocked', () {
      expect(AppInitializer.preferredOrientationsFor(null), isEmpty);
    });
  });
}
