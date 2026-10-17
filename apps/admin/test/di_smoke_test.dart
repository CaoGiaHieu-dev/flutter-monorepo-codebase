import 'package:admin_app/app/app_hooks.dart';
import 'package:admin_app/app/app_profile.dart';
import 'package:admin_app/di/injection.dart';
import 'package:core_base_ui/core_base_ui.dart';
import 'package:core_common/core_common.dart';
import 'package:core_di/core_di.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:platform_app_shell/platform_app_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Boots this app's real, generated DI graph — the one `main.dart` runs.
///
/// `flutter analyze` cannot see a DI ordering bug: an eager `@Singleton`
/// injecting a type a later group registers, a `@preResolve` that throws, a
/// lazy singleton whose dependency no composed module provides. Each one only
/// surfaces at boot as `"<Type> is not registered"`. This test is that boot,
/// minus the widgets, with the platform plugins replaced by their in-memory
/// test doubles.
///
/// It names no module on purpose (only `injection.dart` may — arch_check
/// R10): it checks what the shell resolves, however the manifest composes
/// the app.
///
/// For every platform the manifest declares but the web, times every flavor,
/// the graph is booted with the app's profile registered, as `runShellApp`
/// does, and then held to what `app_manifest.yaml` declares:
/// `checkAppContract` compares each optional contract's `provided` /
/// `absent` with what the graph registered, and asserts the required ones, a
/// screen, unique tab orders and a router that assembles (RULE-63, RULE-81).
/// Each boot names its platform twice — to the shell
/// (`debugAppPlatformOverride`, so the platform's facts reach DI: the
/// secure-storage policy, push) and to the plugins
/// (`debugDefaultTargetPlatformOverride`, so each picks that platform's side).
///
/// The VM cannot be a browser: the web graph is proven by
/// integration_test/boot_test.dart in one (RULE-83).

/// Factories this check does not build: those with a non-nullable
/// `@factoryParam`, which only the screen that creates them can supply — a
/// detail screen's controller takes the id its route passes. Key: the type name
/// (`DetailBloc`). Value: why it cannot be built here. An entry that matches no
/// factory, or one that needs no argument, fails the test, so the list cannot
/// rot. Empty: every factory of this app takes nullable parameters or none.
const _factoriesNeedingArguments = <String, String>{};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  tearDown(resetDependencies);

  for (final platform in appFacts.platforms.keys.where(
    (p) => p != AppPlatform.web,
  )) {
    for (final flavor in appFacts.flavors) {
      test(
        '${platform.name} · ${flavor.name}: the graph boots, every lazy '
        'singleton and factory builds, and the declaration matches it',
        () async {
          debugAppPlatformOverride = platform;
          debugDefaultTargetPlatformOverride = _targetOf(platform);
          addTearDown(() {
            debugAppPlatformOverride = null;
            debugDefaultTargetPlatformOverride = null;
          });
          registerAppProfile(appProfile, platform: platform);
          // The recorder stands in for the locator while the graph registers,
          // so each factory is seen — and built — one at a time.
          final recorder = FactoryRecorder(getIt);
          await configureDependencies(
            environment: flavor.name,
            locator: recorder,
          );

          // Every `@lazySingleton` in the graph built now instead of on first
          // use, and every `@injectable` factory built once — a missing
          // dependency throws here rather than on some screen (RULE-63).
          //
          // A factory takes its `@factoryParam` arguments from the screen that
          // creates it, and here there is none: a nullable parameter gets
          // `null` (HomeProfileBloc's reads "no session contract registered"),
          // an async factory is awaited, and a non-nullable parameter is F01
          // unless the factory is listed in `_factoriesNeedingArguments`. A
          // failure names the factory's type.
          final built = getIt.findAll<Object>(instantiateLazySingletons: true);
          expect(built, isNotEmpty);
          final factories = await recorder.buildEvery(
            notBuilt: _factoriesNeedingArguments,
          );
          expect(factories.problems, isEmpty, reason: factories.explain());

          // The graph is built from the sections the profile registered before
          // it: the router got the app's own `RouterProfile`, not a default.
          expect(getIt<AppRouter>().profile, same(appProfile.router));

          // The same for the locale: the language set is the profile's, and
          // every localization delegate a feature contributes supports every
          // language the app offers — a language the app declares but a feature
          // has no translations for would show that feature's raw keys.
          final languages = getIt<LanguageProvider>().languageSet;
          expect(
            languages.fallback.languageCode,
            appProfile.locale.fallback,
          );
          for (final feature in getAllOrEmpty<IFeatureLocalization>()) {
            for (final locale in languages.supported) {
              expect(
                feature.delegate.isSupported(locale),
                isTrue,
                reason: '${feature.runtimeType} / ${locale.languageCode}',
              );
            }
          }

          final report = checkAppContract(
            appProfile,
            flavor: flavor,
            platform: platform,
          );
          expect(report.problems, isEmpty, reason: report.explain());
        },
      );
    }
  }

  test('every declared platform and flavor is a valid way to start', () {
    // The boot's own question for each `platform / flavor` the manifest
    // declares, with the hooks `main.dart` passes: a platform that declares a
    // `window` needs `appHooks.configureWindow` (P05).
    expect(checkDeclaredStarts(appProfile, appHooks), isEmpty);
  });
}

/// What the plugins see for [platform]. The web is never booted on the VM.
TargetPlatform _targetOf(AppPlatform platform) => switch (platform) {
  AppPlatform.android => TargetPlatform.android,
  AppPlatform.ios => TargetPlatform.iOS,
  AppPlatform.macos => TargetPlatform.macOS,
  AppPlatform.windows => TargetPlatform.windows,
  AppPlatform.linux => TargetPlatform.linux,
  AppPlatform.web => throw StateError('the web is not booted on the VM'),
};
