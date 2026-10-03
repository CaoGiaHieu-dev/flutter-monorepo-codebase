import 'package:core_common/core_common.dart';
import 'package:core_di/core_di.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:platform_app_shell/platform_app_shell.dart';

import 'support/boot_harness.dart';
import 'support/profile_fakes.dart';

/// `runShellApp(profile:)`: the app's declaration is checked before any
/// dependency is built, held to the graph afterwards, and chooses the splash.
/// `runShellApp(configureDependencies:)` — the call every app made before
/// profiles existed — is the same boot it always was.
void main() {
  final harness = BootHarness();
  setUp(harness.setUp);
  tearDown(harness.tearDown);

  group('a platform the manifest does not declare', () {
    testWidgets('stops at the boot-error screen and never starts DI', (
      tester,
    ) async {
      var diCalls = 0;
      var hookCalls = 0;
      // The test binding reports Android; this app declares only iOS.
      final profile = testProfile(
        platforms: {AppPlatform.ios: platformFacts()},
      );

      runShellApp(
        profile: profile,
        hooks: ShellHooks(
          beforeDependencies: (_) async => hookCalls++,
          afterBoot: (_) async => hookCalls++,
        ),
        configureDependencies: () async => diCalls++,
      );
      await pumpUntil(
        tester,
        () => find.byType(BootErrorApp).evaluate().isNotEmpty,
      );

      expect(find.byType(BootErrorApp), findsOneWidget);
      expect(find.textContaining('[P01]'), findsOneWidget);
      expect(
        find.textContaining('`test_app` is running on android'),
        findsOneWidget,
      );
      expect(find.textContaining('declared: ios'), findsOneWidget);
      expect(diCalls, 0, reason: 'configureDependencies must not run');
      expect(hookCalls, 0, reason: 'no hook runs before the boot is valid');
      expect(getIt.isRegistered<AppProfile>(), isFalse);
    });

    testWidgets('follows the platform the test names', (tester) async {
      debugAppPlatformOverride = AppPlatform.linux;
      var diCalls = 0;

      runShellApp(
        profile: testProfile(),
        configureDependencies: () async => diCalls++,
      );
      await pumpUntil(
        tester,
        () => find.byType(BootErrorApp).evaluate().isNotEmpty,
      );

      expect(find.textContaining('is running on linux'), findsOneWidget);
      expect(find.textContaining('declared: android, ios'), findsOneWidget);
      expect(diCalls, 0);
    });
  });

  group('a profile that matches the app', () {
    testWidgets('is registered before DI; hooks run before and after it', (
      tester,
    ) async {
      final log = <String>[];
      AppProfile? seenInDi;
      PlatformFacts? factsSeenInDi;
      final profile = testProfile(
        capabilities: declare(provided: const {'routes', 'splash'}),
      );

      runShellApp(
        profile: profile,
        hooks: ShellHooks(
          beforeDependencies: (runtime) async {
            log.add('beforeDependencies:${runtime.platform.name}');
            expect(runtime.profile, same(profile));
            expect(runtime.isDebug, isTrue);
            expect(getIt.isRegistered<AppProfile>(), isTrue);
          },
          afterBoot: (runtime) async => log.add('afterBoot'),
        ),
        configureDependencies: () async {
          log.add('configureDependencies');
          seenInDi = getItOrNull<AppProfile>();
          factsSeenInDi = getItOrNull<PlatformFacts>();
          getIt.enableRegisteringMultipleInstancesOfOneType();
          registerRequiredShell();
          getIt
            ..registerSingleton<IFeatureRouteModule>(aRoute())
            ..registerSingleton<IAppSplashScreen>(FakeSplash());
        },
      );
      await pumpUntil(tester, () => log.contains('afterBoot'));

      expect(log, [
        'beforeDependencies:android',
        'configureDependencies',
        'afterBoot',
      ]);
      expect(seenInDi, same(profile));
      expect(
        factsSeenInDi,
        same(profile.facts.platformFor(AppPlatform.android)),
      );
      expect(find.byType(BootErrorApp), findsNothing);

      await settleAndTearDown(tester);
    });

    for (final (mode, builds) in [
      (SplashMode.dart, true),
      (SplashMode.native, false),
    ]) {
      testWidgets('splash: ${mode.name} ${builds ? 'builds' : 'skips'} the '
          'Dart splash', (tester) async {
        var splashBuilt = false;
        var booted = false;

        runShellApp(
          profile: testProfile(
            platforms: {AppPlatform.android: platformFacts(splash: mode)},
            capabilities: declare(provided: const {'routes', 'splash'}),
          ),
          hooks: ShellHooks(afterBoot: (_) async => booted = true),
          configureDependencies: () async {
            getIt.enableRegisteringMultipleInstancesOfOneType();
            registerRequiredShell();
            getIt
              ..registerSingleton<IFeatureRouteModule>(aRoute())
              ..registerSingleton<IAppSplashScreen>(
                FakeSplash(() => splashBuilt = true),
              );
          },
        );
        await pumpUntil(tester, () => booted);

        expect(booted, isTrue);
        expect(splashBuilt, builds);

        await settleAndTearDown(tester);
      });
    }
  });

  group('a declaration that does not match the graph', () {
    testWidgets('stops after DI with the composition problem', (tester) async {
      var booted = false;

      runShellApp(
        // `splash` is declared provided, but nothing registers it.
        profile: testProfile(
          capabilities: declare(provided: const {'routes', 'splash'}),
        ),
        hooks: ShellHooks(afterBoot: (_) async => booted = true),
        configureDependencies: () async {
          getIt.enableRegisteringMultipleInstancesOfOneType();
          registerRequiredShell();
          getIt.registerSingleton<IFeatureRouteModule>(aRoute());
        },
      );
      await pumpUntil(
        tester,
        () => find.byType(BootErrorApp).evaluate().isNotEmpty,
      );

      expect(find.textContaining('[C02]'), findsOneWidget);
      expect(find.textContaining('`capabilities.splash`'), findsOneWidget);
      expect(booted, isFalse, reason: 'afterBoot must not run');
    });
  });

  group('without a profile', () {
    testWidgets('the boot is the one every app had: no profile, same DI', (
      tester,
    ) async {
      var diCalls = 0;
      var splashBuilt = false;
      final errors = <Object>[];

      runShellApp(
        configureDependencies: () async {
          diCalls++;
          registerRequiredShell();
          getIt.registerSingleton<IAppSplashScreen>(
            FakeSplash(() => splashBuilt = true),
          );
        },
        onError: (error, _) => errors.add(error),
      );
      await pumpUntil(tester, () => splashBuilt);

      expect(diCalls, 1);
      expect(splashBuilt, isTrue);
      expect(getIt.isRegistered<AppProfile>(), isFalse);
      expect(getIt.isRegistered<PlatformFacts>(), isFalse);
      expect(find.byType(BootErrorApp), findsNothing);
      expect(errors, isEmpty);

      await settleAndTearDown(tester);
    });

    test('hooks that need an AppRuntime need a profile', () {
      for (final hooks in [
        ShellHooks(beforeDependencies: (_) async {}),
        ShellHooks(afterBoot: (_) async {}),
      ]) {
        expect(
          () => runShellApp(hooks: hooks, configureDependencies: () async {}),
          throwsArgumentError,
        );
      }
    });

    test('the fatal callback is passed once, not twice', () {
      expect(
        () => runShellApp(
          hooks: const ShellHooks(onError: _ignore),
          onError: _ignore,
          configureDependencies: () async {},
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('validateBoot', () {
    AppRuntime runtime({
      required AppPlatform platform,
      required Flavor flavor,
      bool isDebug = true,
      AppProfile? profile,
    }) => AppRuntime(
      profile: profile ?? testProfile(),
      flavor: flavor,
      platform: platform,
      isDebug: isDebug,
    );

    test('a declared platform and flavor is clean', () {
      expect(
        validateBoot(runtime(platform: AppPlatform.ios, flavor: Flavor.prod)),
        isEmpty,
      );
    });

    test('an undeclared platform is P01', () {
      final problems = validateBoot(
        runtime(platform: AppPlatform.web, flavor: Flavor.dev),
      );

      expect(problems.map((p) => p.code), ['P01']);
    });

    test('ALLOW_UNDECLARED_PLATFORM turns P01 into a warning only', () {
      final problems = validateBoot(
        runtime(platform: AppPlatform.web, flavor: Flavor.dev),
        allowUndeclaredPlatform: true,
      );

      expect(problems, isEmpty);
    });

    test('it does not excuse an undeclared flavor', () {
      final problems = validateBoot(
        runtime(
          platform: AppPlatform.web,
          flavor: Flavor.dev,
          profile: AppProfile(
            facts: AppFacts(
              id: 'test_app',
              name: 'Test App',
              flavors: const {Flavor.prod},
              platforms: {AppPlatform.android: platformFacts()},
              sslPinning: const SslPinningPolicy.none(),
            ),
          ),
        ),
        allowUndeclaredPlatform: true,
      );

      expect(problems.map((p) => p.code), ['P02']);
    });

    group('required environment keys', () {
      final profile = AppProfile(
        facts: AppFacts(
          id: 'test_app',
          name: 'Test App',
          flavors: const {Flavor.dev, Flavor.prod},
          platforms: {AppPlatform.android: platformFacts()},
          env: const [
            EnvRule(key: 'BASE_URL', value: '', requiredIn: {Flavor.prod}),
          ],
          sslPinning: const SslPinningPolicy({
            Flavor.dev: SslPinning.disabled('test'),
            Flavor.prod: SslPinning.disabled('test'),
          }),
        ),
      );

      test('stop a non-debug build', () {
        final problems = validateBoot(
          runtime(
            platform: AppPlatform.android,
            flavor: Flavor.prod,
            isDebug: false,
            profile: profile,
          ),
        );

        expect(problems.map((p) => p.code), ['P03']);
      });

      test('never stop a debug build', () {
        expect(
          validateBoot(
            runtime(
              platform: AppPlatform.android,
              flavor: Flavor.prod,
              profile: profile,
            ),
          ),
          isEmpty,
        );
      });
    });
  });

  group('showsBootDiagnostics', () {
    test('every debug or profile build, and every non-prod flavor', () {
      for (final flavor in Flavor.values) {
        expect(showsBootDiagnostics(flavor, isRelease: false), isTrue);
      }
      expect(showsBootDiagnostics(Flavor.dev, isRelease: true), isTrue);
      expect(showsBootDiagnostics(Flavor.staging, isRelease: true), isTrue);
    });

    test('a production release keeps its users out of the details', () {
      expect(showsBootDiagnostics(Flavor.prod, isRelease: true), isFalse);
    });
  });
}

void _ignore(Object error, StackTrace stack) {}
