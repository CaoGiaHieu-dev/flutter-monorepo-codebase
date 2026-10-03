import 'package:admin_app/app/app_profile.dart';
import 'package:core_common/core_common.dart';
import 'package:flutter_test/flutter_test.dart';

/// Migration neutrality: what `apps/admin` declares must reproduce what the
/// app did before it could declare anything — the same switches on every
/// platform it can run on, the same flavors, no pinning — and every optional
/// contract it does not compose stays declared absent, with a reason.
///
/// A change to `app_manifest.yaml` that moves one of these is a behaviour
/// change; this test says so, and the manifest edit and this test change
/// together.
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
      expect(appFacts.name, 'Codebase Admin');
      expect(appProfile.facts, same(appFacts));
    });

    test('declare the three flavors the app was always built as', () {
      expect(appFacts.flavors, {Flavor.dev, Flavor.staging, Flavor.prod});
    });

    test('declare web and the desktop platforms, all still to be created', () {
      expect(appFacts.platforms.keys, declared);
      for (final platform in appFacts.platforms.values) {
        expect(platform.runner, RunnerKind.scaffold);
      }
    });

    test('keep the switches as they were: native splash, deep links on', () {
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

    test('require what a working build always needed', () {
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
      // What the shell did before an app could tune it. A section an app sets
      // is a behaviour change, so the value here and the app move together.
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
