import 'package:core_common/core_common.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/app/app_profile.dart';

/// Migration neutrality: what `apps/mobile` declares must reproduce what the
/// app did before it could declare anything — the same platforms with the same
/// switches, the same flavors, the same certificate pinning outcome (none) —
/// and anything the profile itself sets must be the template default.
///
/// A change to `app_manifest.yaml` that moves one of these is a behaviour
/// change; this test says so, and the manifest edit and this test change
/// together.
void main() {
  group('the facts', () {
    test('are for this app', () {
      expect(appFacts.id, 'mobile');
      expect(appFacts.name, 'Codebase');
      expect(appProfile.facts, same(appFacts));
    });

    test('declare the three flavors the app was always built as', () {
      expect(appFacts.flavors, {Flavor.dev, Flavor.staging, Flavor.prod});
    });

    test('declare android and ios, nothing else', () {
      expect(appFacts.platforms.keys, {AppPlatform.android, AppPlatform.ios});
    });

    test('keep every platform switch as it was', () {
      for (final entry in appFacts.platforms.entries) {
        final platform = entry.value;
        expect(platform.runner, RunnerKind.committed, reason: entry.key.name);
        expect(platform.deepLinks, isTrue, reason: entry.key.name);
        expect(platform.push, isTrue, reason: entry.key.name);
        expect(
          platform.orientation,
          OrientationPolicy.phonesPortrait,
          reason: entry.key.name,
        );
        expect(platform.window, isNull, reason: entry.key.name);
      }
    });

    test(
      'keep the splash fork of the old bootstrap: iOS native, Android Dart',
      () {
        expect(
          appFacts.platformFor(AppPlatform.android)!.splash,
          SplashMode.dart,
        );
        expect(
          appFacts.platformFor(AppPlatform.ios)!.splash,
          SplashMode.native,
        );
      },
    );

    test('still pin nothing, on every flavor — now as a stated decision', () {
      for (final flavor in Flavor.values) {
        expect(appFacts.sslPinning.hashesFor(flavor), isEmpty);
        expect(
          appFacts.sslPinning.decisionFor(flavor),
          isA<DisabledSsl>(),
          reason: flavor.name,
        );
      }
    });

    test('require what a working build always needed', () {
      final required = {
        for (final rule in appFacts.env) rule.key: rule.requiredIn,
      };
      expect(required, {
        'BASE_URL': {Flavor.prod},
        'APP_NAME': {Flavor.staging, Flavor.prod},
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
    test(
      'adds nothing to the facts yet: every tuning value is the default',
      () {
        // `AppProfile` has no tuning section in this version; when one is added
        // its default must equal today's behaviour, and this is where the app
        // proves it passes the default.
        expect(const AppProfile(facts: appFacts).facts, same(appFacts));
      },
    );
  });
}
