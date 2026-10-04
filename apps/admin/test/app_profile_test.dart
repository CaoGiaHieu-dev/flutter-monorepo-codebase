import 'dart:io';

import 'package:admin_app/app/app_profile.dart';
import 'package:core_common/core_common.dart';
import 'package:flutter_test/flutter_test.dart';

/// What `apps/admin` declares: the same switches on every platform it can run
/// on, the three flavors, no pinning — and every optional contract it does
/// not compose declared absent, with a reason.
///
/// A change to `app_manifest.yaml` that moves one of these is a behaviour
/// change; this test says so, and the manifest edit and this test change
/// together. The display name is the exception: it is read from the manifest.
void main() {
  const declared = {
    AppPlatform.web,
    AppPlatform.windows,
    AppPlatform.macos,
    AppPlatform.linux,
  };

  group('the facts', () {
    test('are for this app', () {
      expect(appFacts.id, 'admin');
      expect(appFacts.name, _manifestAppName());
      expect(appProfile.facts, same(appFacts));
    });

    test('declare the three flavors', () {
      expect(appFacts.flavors, {Flavor.dev, Flavor.staging, Flavor.prod});
    });

    test('declare web and the desktop platforms, all still to be created', () {
      expect(appFacts.platforms.keys, declared);
      for (final platform in appFacts.platforms.values) {
        expect(platform.runner, RunnerKind.scaffold);
      }
    });

    test('declare native splash and deep links on every platform', () {
      for (final entry in appFacts.platforms.entries) {
        final platform = entry.value;
        expect(platform.splash, SplashMode.native, reason: entry.key.name);
        expect(platform.deepLinks, isTrue, reason: entry.key.name);
        expect(
          platform.orientation,
          OrientationPolicy.phonesPortrait,
          reason: entry.key.name,
        );
        expect(platform.window, isNull, reason: entry.key.name);
      }
    });

    test('send no push: core_notifications is not composed', () {
      for (final entry in appFacts.platforms.entries) {
        expect(entry.value.push, isFalse, reason: entry.key.name);
      }
    });

    test('pin nothing: no declared platform can pin TLS', () {
      expect(declared.any((p) => p.canPinTls), isFalse);
      for (final flavor in Flavor.values) {
        expect(appFacts.sslPinning.decisionFor(flavor), isNull);
        expect(appFacts.sslPinning.hashesFor(flavor), isEmpty);
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

    test(
      'provide the session, routes, tabs, tree wrappers and localization',
      () {
        for (final id in const [
          'session_state',
          'session_gateway',
          'session_refresh',
          'sign_in',
          'routes',
          'tabs',
          'tree_wrappers',
          'localization',
        ]) {
          expect(
            appFacts.capabilities[id],
            isA<ProvidedCapability>(),
            reason: id,
          );
        }
      },
    );

    test('state why each fallback of the shell is in use, permanently', () {
      for (final id in const [
        'dashboard',
        'entry',
        'post_sign_in',
        'splash',
        'error_reporter',
        'analytics',
      ]) {
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
