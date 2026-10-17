import 'dart:io';

import 'package:core_common/core_common.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/app/app_profile.dart';

/// What `apps/mobile` declares: android and ios (committed runners) with their
/// switches, web and linux (generated runners) with push and deep links off,
/// the three flavors, no certificate pinning (as a stated decision), and a profile that
/// leaves every tuning section at the template default.
///
/// A change to `app_manifest.yaml` that moves one of these is a behaviour
/// change; this test says so, and the manifest edit and this test change
/// together. The display name is the exception: it is read from the manifest.
void main() {
  group('the facts', () {
    test('are for this app', () {
      expect(appFacts.id, 'mobile');
      expect(appFacts.name, _manifestAppName());
      expect(appProfile.facts, same(appFacts));
    });

    test('declare the three flavors', () {
      expect(appFacts.flavors, {Flavor.dev, Flavor.staging, Flavor.prod});
    });

    test('declare android and ios (committed), web and linux (generated)', () {
      expect(appFacts.platforms.keys, {
        AppPlatform.android,
        AppPlatform.ios,
        AppPlatform.web,
        AppPlatform.linux,
      });
    });

    test('declare every platform switch of the committed runners', () {
      for (final platform in const [AppPlatform.android, AppPlatform.ios]) {
        final facts = appFacts.platformFor(platform)!;
        expect(facts.runner, RunnerKind.committed, reason: platform.name);
        expect(facts.deepLinks, isTrue, reason: platform.name);
        expect(facts.push, isTrue, reason: platform.name);
        expect(
          facts.secureStorage,
          SecureStoragePolicy.required,
          reason: platform.name,
        );
      }
    });

    test('derive push and deep links off on the generated web and linux '
        'runners; linux keeps secure values in memory without a Secret '
        'Service', () {
      for (final platform in const [AppPlatform.web, AppPlatform.linux]) {
        final facts = appFacts.platformFor(platform)!;
        expect(facts.runner, RunnerKind.scaffold, reason: platform.name);
        expect(facts.deepLinks, isFalse, reason: platform.name);
        expect(facts.push, isFalse, reason: platform.name);
      }
      expect(
        appFacts.platformFor(AppPlatform.web)!.secureStorage,
        SecureStoragePolicy.required,
      );
      expect(
        appFacts.platformFor(AppPlatform.linux)!.secureStorage,
        SecureStoragePolicy.memoryFallback,
      );
    });

    test('lock phones to portrait and set no window, on every platform', () {
      for (final entry in appFacts.platforms.entries) {
        expect(
          entry.value.orientation,
          OrientationPolicy.phonesPortrait,
          reason: entry.key.name,
        );
        expect(entry.value.window, isNull, reason: entry.key.name);
      }
    });

    test(
      'split the splash by platform: iOS native, Android, web and linux Dart',
      () {
        expect(
          appFacts.platformFor(AppPlatform.android)!.splash,
          SplashMode.dart,
        );
        expect(
          appFacts.platformFor(AppPlatform.ios)!.splash,
          SplashMode.native,
        );
        expect(
          appFacts.platformFor(AppPlatform.web)!.splash,
          SplashMode.dart,
        );
        expect(
          appFacts.platformFor(AppPlatform.linux)!.splash,
          SplashMode.dart,
        );
      },
    );

    test('pin nothing, on every flavor, as a stated decision', () {
      for (final flavor in Flavor.values) {
        expect(appFacts.sslPinning.hashesFor(flavor), isEmpty);
        expect(
          appFacts.sslPinning.decisionFor(flavor),
          isA<DisabledSsl>(),
          reason: flavor.name,
        );
      }
    });

    test('require what a working build needs', () {
      final required = {
        for (final rule in appFacts.env) rule.key: rule.requiredIn,
      };
      expect(required, {
        'BASE_URL': {Flavor.prod},
        // The title falls back to `app.name`, so a missing APP_NAME never stops a boot.
        'APP_NAME': isEmpty,
      });
    });

    test('declare every optional contract the sample modules provide', () {
      for (final id in const [
        'session_state',
        'session_gateway',
        'session_refresh',
        'sign_in',
        'routes',
        'tabs',
        'dashboard',
        'entry',
        'post_sign_in',
        'splash',
        'tree_wrappers',
        'localization',
      ]) {
        expect(
          appFacts.capabilities[id],
          isA<ProvidedCapability>(),
          reason: id,
        );
      }
    });

    test('state why there is no crash reporter and no analytics', () {
      for (final id in const ['error_reporter', 'analytics']) {
        final capability = appFacts.capabilities[id];
        expect(capability, isA<AbsentCapability>(), reason: id);
        expect((capability! as AbsentCapability).reason, isNotEmpty);
      }
    });
  });

  group('the profile', () {
    test('tunes nothing: every section is the template default', () {
      // The shell's own defaults. A section an app sets is a behaviour
      // change, so the value here and the app move together.
      const defaults = DisplayProfile();
      final display = appProfile.display;
      expect(display.designSize.width, defaults.designSize.width);
      expect(display.designSize.height, defaults.designSize.height);
      expect(display.textScaleMax, defaults.textScaleMax);
      expect(display.splitScreenMode, defaults.splitScreenMode);
      expect(display.phoneMaxShortestSide, defaults.phoneMaxShortestSide);
      expect(display.scale.keys, defaults.scale.keys);
      expect(display.scale[WindowClass.expanded], isA<FixedScale>());

      expect(appProfile.router.entry, EntryPolicy.firstLaunch);
      expect(appProfile.router.fallbackPath, isNull);

      // Language, theme and the default HTTP client are the template's too.
      const locale = LocaleProfile();
      expect(appProfile.locale.supported, locale.supported);
      expect(appProfile.locale.fallback, locale.fallback);
      expect(appProfile.locale.initial, locale.initial);

      const theme = ThemeProfile();
      expect(appProfile.theme.mode, theme.mode);
      expect(appProfile.theme.light, theme.light);
      expect(appProfile.theme.dark, theme.dark);

      const network = NetworkProfile();
      expect(appProfile.network.connectTimeout, network.connectTimeout);
      expect(appProfile.network.receiveTimeout, network.receiveTimeout);
      expect(appProfile.network.sendTimeout, network.sendTimeout);
      expect(appProfile.network.headers, network.headers);
      expect(appProfile.network.followRedirects, network.followRedirects);
    });
  });
}

/// The `name:` under `app:` in `app_manifest.yaml` — what `composer sync`
/// turns into `appFacts.name`. Read from the file so renaming the app (the
/// "Make it yours" step) does not break this test. A test runs from the
/// package directory, where the manifest sits.
String _manifestAppName() {
  final manifest = File('app_manifest.yaml').readAsLinesSync();
  final app = manifest.indexWhere((line) => line.trimRight() == 'app:');
  for (final line in manifest.skip(app + 1)) {
    if (line.isNotEmpty && !line.startsWith(' ')) break;
    final match = RegExp(r'^\s+name:\s*(.+?)\s*$').firstMatch(line);
    if (match != null) return match.group(1)!;
  }
  throw StateError('no `app.name` in app_manifest.yaml');
}
