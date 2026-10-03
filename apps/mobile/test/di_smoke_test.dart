import 'dart:io';

import 'package:core_base_ui/core_base_ui.dart';
import 'package:core_common/core_common.dart';
import 'package:core_di/core_di.dart';
import 'package:drift/drift.dart' show GeneratedDatabase;
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/app/app_hooks.dart';
import 'package:mobile_app/app/app_profile.dart';
import 'package:mobile_app/di/injection.dart';
import 'package:platform_app_shell/platform_app_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Boots this app's real, generated DI graph — the one `main.dart` runs.
///
/// `flutter analyze` cannot see a DI ordering bug: an eager `@Singleton`
/// injecting a type a later group registers, a `@preResolve` that throws, a
/// lazy singleton whose dependency no composed module provides. Each one only
/// surfaces at boot as `"<Type> is not registered"`. This test is that boot,
/// minus the widgets, with every platform plugin the graph touches replaced
/// by a test double:
///
/// - storage: the plugins' own in-memory stores;
/// - `path_provider`: a temporary directory, for the package-owned Drift
///   databases the graph opens (`@preResolve`) on a background isolate;
/// - Firebase, messaging and local notifications — `PushNotificationService`
///   initialises all three while DI runs (`@PostConstruct(preResolve: true)`):
///   FlutterFire's own Pigeon test API for Firebase core, and a stub of each
///   plugin's method channel. A test runs no plugin registrant, so the
///   Android local-notifications implementation is registered by hand — a
///   test binding reports Android as its target platform.
///
/// It names no module on purpose (only `injection.dart` may — arch_check
/// R10): it checks what the shell resolves, however the manifest composes
/// the app. Like the app itself it compiles against
/// `lib/firebase/firebase_options_*.dart` (gitignored; CI writes stubs).
///
/// For every flavor the manifest declares, the graph is booted with the app's
/// profile registered, as `runShellApp` does, and then held to what
/// `app_manifest.yaml` declares: `checkAppContract` compares each optional
/// contract's `provided` / `absent` with what the graph registered, and
/// asserts the required ones, a screen, unique tab orders and a router that
/// assembles (RULE-63, RULE-81).
///
/// A VM test reports Android and never the web, so the platform is named
/// explicitly instead of read from the device.
const _platform = AppPlatform.android;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestFirebaseCoreHostApi.setUp(_FirebaseCoreHost());
  AndroidFlutterLocalNotificationsPlugin.registerWith();

  late Directory documents;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    documents = Directory.systemTemp.createTempSync('di_smoke_');
    messenger
      ..setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (_) async => documents.path,
      )
      ..setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/firebase_messaging'),
        (call) async => switch (call.method) {
          'Messaging#requestPermission' ||
          'Messaging#getNotificationSettings' => {'authorizationStatus': 1},
          'Messaging#getToken' => {'token': 'di-smoke-test'},
          // getInitialMessage (none), startBackgroundIsolate, …
          _ => null,
        },
      )
      ..setMockMethodCallHandler(
        const MethodChannel('dexterous.com/flutter/local_notifications'),
        (call) async => switch (call.method) {
          'initialize' => true,
          // getNotificationAppLaunchDetails (not launched by one), channels…
          _ => null,
        },
      );
  });

  tearDown(() async {
    // Each package-owned database runs on its own isolate; GetIt's reset
    // does not close it, and the next boot would open a second instance.
    for (final database in getIt.findAll<GeneratedDatabase>()) {
      await database.close();
    }
    await resetDependencies();
    messenger
      ..setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        null,
      )
      ..setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/firebase_messaging'),
        null,
      )
      ..setMockMethodCallHandler(
        const MethodChannel('dexterous.com/flutter/local_notifications'),
        null,
      );
    documents.deleteSync(recursive: true);
  });

  for (final flavor in appFacts.flavors) {
    test(
      'the ${flavor.name} graph boots, every lazy singleton builds and the '
      'declaration matches it',
      () async {
        registerAppProfile(appProfile, platform: _platform);
        await configureDependencies(environment: flavor.name);

        // Every `@lazySingleton` in the graph, built now instead of on first
        // use — a missing dependency throws here rather than on some screen.
        final singletons = getIt.findAll<Object>(
          instantiateLazySingletons: true,
        );
        expect(singletons, isNotEmpty);

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
          platform: _platform,
        );
        expect(report.problems, isEmpty, reason: report.explain());
      },
    );
  }

  test('every declared platform and flavor is a valid way to start', () {
    // The boot's own question for each `platform / flavor` the manifest
    // declares, with the hooks `main.dart` passes: a platform that declares a
    // `window` needs `appHooks.configureWindow` (P05).
    expect(checkDeclaredStarts(appProfile, appHooks), isEmpty);
  });
}

/// Firebase core's host side, as a real one behaves on a fresh install: no
/// app configured natively, and `initializeApp` echoes the options the app
/// passes. FlutterFire's own `setupFirebaseCoreMocks()` answers
/// `initializeCore` with a default app on fixed options, which then collides
/// with the app's own (`core/duplicate-app`).
class _FirebaseCoreHost implements TestFirebaseCoreHostApi {
  @override
  Future<List<CoreInitializeResponse>> initializeCore() async => [];

  @override
  Future<CoreInitializeResponse> initializeApp(
    String appName,
    CoreFirebaseOptions initializeAppRequest,
  ) async => CoreInitializeResponse(
    name: appName,
    options: initializeAppRequest,
    pluginConstants: {},
  );

  @override
  Future<CoreFirebaseOptions> optionsFromResource() =>
      throw UnsupportedError('the app always passes its options');
}
