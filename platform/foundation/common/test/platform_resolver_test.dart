import 'package:core_common/core_common.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => debugAppPlatformOverride = null);

  group('resolveAppPlatform', () {
    test('maps every target platform it supports', () {
      expect(
        {
          for (final target in TargetPlatform.values)
            if (target != TargetPlatform.fuchsia)
              target: resolveAppPlatform(isWeb: false, target: target),
        },
        {
          TargetPlatform.android: AppPlatform.android,
          TargetPlatform.iOS: AppPlatform.ios,
          TargetPlatform.macOS: AppPlatform.macos,
          TargetPlatform.windows: AppPlatform.windows,
          TargetPlatform.linux: AppPlatform.linux,
        },
      );
    });

    test('the web is checked first, whatever the browser reports', () {
      for (final target in TargetPlatform.values) {
        expect(
          resolveAppPlatform(isWeb: true, target: target),
          AppPlatform.web,
          reason: target.name,
        );
      }
    });

    test('fuchsia is refused rather than guessed', () {
      expect(
        () => resolveAppPlatform(isWeb: false, target: TargetPlatform.fuchsia),
        throwsUnsupportedError,
      );
    });

    test('a test binding reports Android and never the web', () {
      expect(resolveAppPlatform(), AppPlatform.android);
    });

    test('follows debugDefaultTargetPlatformOverride', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      expect(resolveAppPlatform(), AppPlatform.ios);
    });
  });

  group('debugAppPlatformOverride', () {
    test('answers a call with no arguments', () {
      debugAppPlatformOverride = AppPlatform.linux;

      expect(resolveAppPlatform(), AppPlatform.linux);
    });

    test('is beaten by an explicit argument', () {
      debugAppPlatformOverride = AppPlatform.linux;

      expect(resolveAppPlatform(isWeb: true), AppPlatform.web);
      expect(
        resolveAppPlatform(target: TargetPlatform.macOS),
        AppPlatform.macos,
      );
    });
  });
}
