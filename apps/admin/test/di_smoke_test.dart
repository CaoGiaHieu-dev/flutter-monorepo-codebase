import 'package:admin_app/di/injection.dart';
import 'package:core_common/core_common.dart';
import 'package:core_di/core_di.dart';
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
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  tearDown(resetDependencies);

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
  getItOrNull<DashboardRouteModule>();
  getItOrNull<IAuthRefreshListenable>();
  getItOrNull<IAuthSessionState>();
  getItOrNull<IAuthSessionGateway>();
  getItOrNull<IAuthStatusStream>();
  getItOrNull<IAuthActionHandler>();
  getItOrNull<AuthNavigator>();
  getItOrNull<HomeNavigator>();
  getItOrNull<IErrorReporter>();
  getItOrNull<IAnalytics>();

  // Registered by the shell itself: required, not optional.
  getIt<ILanguageStorage>();
  getIt<IThemeStorage>();
  getIt<SslPinningConfig>();

  // Assembles the GoRouter from every contribution above; GoRouter asserts
  // on a malformed tree (duplicate or missing paths) while it is built.
  final router = getIt<AppRouter>().router;
  expect(router.configuration.routes, isNotEmpty);
}
