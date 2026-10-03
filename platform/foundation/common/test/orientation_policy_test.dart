import 'package:core_common/core_common.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// K8 — what an app says about orientation (`platforms.<p>.orientation`) and
/// the phone threshold (`DisplayProfile.phoneMaxShortestSide`) reaches
/// `AppInitializer.preferredOrientationsFor`. The defaults are today's rule —
/// `app_initializer_test.dart` holds that on its own — and an app value
/// changes it.
void main() {
  group('the default is the phone rule of before', () {
    test('no policy given behaves as phonesPortrait at 600', () {
      for (final side in [320.0, 599.9, 600.0, 1024.0, null]) {
        expect(
          AppInitializer.preferredOrientationsFor(side),
          AppInitializer.preferredOrientationsFor(
            side,
            policy: OrientationPolicy.phonesPortrait,
            phoneMaxShortestSide: const DisplayProfile().phoneMaxShortestSide,
          ),
          reason: 'shortest side $side',
        );
      }
    });
  });

  group('a declared policy changes it', () {
    test('free never locks, even a phone', () {
      expect(
        AppInitializer.preferredOrientationsFor(
          375,
          policy: OrientationPolicy.free,
        ),
        isEmpty,
      );
    });

    test('portrait always locks to portrait, even a tablet', () {
      for (final side in [375.0, 1024.0, null]) {
        expect(
          AppInitializer.preferredOrientationsFor(
            side,
            policy: OrientationPolicy.portrait,
          ),
          [DeviceOrientation.portraitUp],
          reason: 'shortest side $side',
        );
      }
    });

    test('landscape always locks to landscape, even a phone', () {
      for (final side in [375.0, 1024.0, null]) {
        expect(
          AppInitializer.preferredOrientationsFor(
            side,
            policy: OrientationPolicy.landscape,
          ),
          [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight],
          reason: 'shortest side $side',
        );
      }
    });
  });

  group('the phone threshold is the app\'s', () {
    test('a larger threshold makes a 700 dp display a phone', () {
      expect(AppInitializer.preferredOrientationsFor(700), isEmpty);
      expect(
        AppInitializer.preferredOrientationsFor(
          700,
          phoneMaxShortestSide: 720,
        ),
        [DeviceOrientation.portraitUp],
      );
    });

    test('a smaller threshold frees a 500 dp display', () {
      expect(
        AppInitializer.preferredOrientationsFor(500),
        [DeviceOrientation.portraitUp],
      );
      expect(
        AppInitializer.preferredOrientationsFor(
          500,
          phoneMaxShortestSide: 400,
        ),
        isEmpty,
      );
    });
  });
}
