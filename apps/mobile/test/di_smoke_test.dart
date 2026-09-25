import 'dart:io';

import 'package:core_common/core_common.dart';
import 'package:core_di/core_di.dart';
import 'package:core_network/core_network.dart';
import 'package:drift/drift.dart' show GeneratedDatabase;
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/di/injection.dart';
import 'package:platform_app_shell/platform_app_shell.dart';
import 'package:platform_shell_adapters/platform_shell_adapters.dart';
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

  for (final environment in const ['dev', 'staging', 'prod']) {
    test(
      'the $environment graph boots and every lazy singleton builds',
      () async {
        await configureDependencies(environment: environment);

        // Every `@lazySingleton` in the graph, built now instead of on first
        // use — a missing dependency throws here rather than on some screen.
        final singletons = getIt.findAll<Object>(
          instantiateLazySingletons: true,
        );
        expect(singletons, isNotEmpty);

        _expectShellContractsResolve();
      },
    );
  }
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

/// What the app shell looks up at boot and while routing, resolved exactly
/// the way the shell does — optional contributions through
/// `getAllOrEmpty` / `getItOrNull`, so an absent module is fine but a
/// registered one that cannot be built fails.
void _expectShellContractsResolve() {
  final routes = getAllOrEmpty<IFeatureRouteModule>().toList();
  final tabs = getAllOrEmpty<INavDestinationModule>().toList();
  expect(
    [...routes, ...tabs],
    isNotEmpty,
    reason: 'an app with no route module and no nav tab has no screen',
  );
  expect(
    tabs.map((t) => t.order).toSet(),
    hasLength(tabs.length),
    reason: 'INavDestinationModule.order is the tab sort key — keep it unique',
  );
  getAllOrEmpty<IFeatureLocalization>().toList();
  getAllOrEmpty<IAppTreeWrapper>().toList();

  getItOrNull<IAppSplashScreen>();
  getItOrNull<IAppEntryLocation>();
  getItOrNull<IDashboardRouteModule>();
  getItOrNull<ISessionRefreshListenable>();
  getItOrNull<ISessionState>();
  getItOrNull<ISessionGateway>();
  getItOrNull<ISessionStatusStream>();
  getItOrNull<ISignInLocation>();
  getItOrNull<IPostSignInLocation>();
  getItOrNull<IErrorReporter>();
  getItOrNull<IAnalytics>();

  // Registered by the shell itself (`platform_shell_adapters`): required,
  // not optional.
  getIt<ILanguageStorage>();
  getIt<IThemeStorage>();
  getIt<AppBootStorage>();
  getIt<NetworkConfig>();
  getIt<SslPinningConfig>();

  // `core_network` hooks its Dio classifier into the kernel's ErrorHandler
  // while the `core` group initialises — before any client exists — so a
  // DioException never degrades to the generic "unknown error".
  expect(
    ErrorHandler.classifiers.whereType<DioFailureClassifier>(),
    hasLength(1),
    reason: 'DioFailureClassifier must register itself during DI',
  );

  // Assembles the GoRouter from every contribution above; GoRouter asserts
  // on a malformed tree (duplicate or missing paths) while it is built.
  final router = getIt<AppRouter>().router;
  expect(router.configuration.routes, isNotEmpty);
}
