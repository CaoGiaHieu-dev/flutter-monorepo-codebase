import 'package:core_common/core_common.dart';
import 'package:core_di/core_di.dart';
import 'package:dynamic_logger/dynamic_logger.dart';
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
      ShellHooks? hooksSeenInDi;
      final profile = testProfile(
        capabilities: declare(provided: const {'routes', 'splash'}),
      );
      final hooks = ShellHooks(
        beforeDependencies: (runtime) async {
          log.add('beforeDependencies:${runtime.platform.name}');
          expect(runtime.profile, same(profile));
          expect(runtime.isDebug, isTrue);
          expect(getIt.isRegistered<AppProfile>(), isTrue);
          expect(getIt.isRegistered<ShellHooks>(), isTrue);
        },
        afterBoot: (runtime) async => log.add('afterBoot'),
      );

      runShellApp(
        profile: profile,
        hooks: hooks,
        configureDependencies: () async {
          log.add('configureDependencies');
          seenInDi = getItOrNull<AppProfile>();
          factsSeenInDi = getItOrNull<PlatformFacts>();
          hooksSeenInDi = getItOrNull<ShellHooks>();
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
      expect(hooksSeenInDi, same(hooks));
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

  group('handleCompositionReport', () {
    late List<({int level, String message})> logged;

    setUp(() {
      logged = [];
      DynamicLogger.configure(
        logHandler: (
          message, {
          error,
          level = 0,
          name = '',
          sequenceNumber,
          stackTrace,
          time,
          zone,
        }) => logged.add((level: level, message: message)),
      );
      getIt.enableRegisteringMultipleInstancesOfOneType();
      registerRequiredShell();
      getIt.registerSingleton<IFeatureRouteModule>(aRoute());
    });
    tearDown(DynamicLogger.reset);

    /// What `checkAppContract` says of this graph for an app that declares
    /// the splash `provided`, which nothing registers: one `C02`.
    CompositionReport mismatch(Flavor flavor) => checkAppContract(
      testProfile(capabilities: declare(provided: const {'routes', 'splash'})),
      flavor: flavor,
      platform: AppPlatform.android,
    );

    testWidgets('a clean report goes on without a word', (tester) async {
      final report = checkAppContract(
        testProfile(),
        flavor: Flavor.prod,
        platform: AppPlatform.android,
      );

      expect(report.isClean, isTrue);
      expect(handleCompositionReport(report, isRelease: true), isTrue);
      await tester.pump();

      expect(find.byType(BootErrorApp), findsNothing);
      expect(logged, isEmpty);
    });

    testWidgets('a production release logs it, reports it as non-fatal and '
        'goes on', (tester) async {
      final reporter = FakeReporter();
      getIt.registerSingleton<IErrorReporter>(reporter);
      final seen = <Object>[];

      final goesOn = handleCompositionReport(
        mismatch(Flavor.prod),
        isRelease: true,
        onNonFatalError: (error, _) => seen.add(error),
      );
      await tester.pump();

      expect(goesOn, isTrue, reason: 'RULE-05: the app must still run');
      expect(find.byType(BootErrorApp), findsNothing);
      expect(logged, hasLength(1));
      expect(logged.single.level, 1000, reason: 'an ERROR');
      expect(logged.single.message, contains('[C02]'));
      expect(seen, hasLength(1));
      expect(seen.single, isA<StateError>());
      expect('${seen.single}', contains('[C02]'));
      expect(reporter.recorded, hasLength(1));
      expect(reporter.recorded.single.fatal, isFalse);
    });

    for (final flavor in [Flavor.dev, Flavor.staging]) {
      testWidgets('a ${flavor.name} release still stops with the details', (
        tester,
      ) async {
        final reporter = FakeReporter();
        getIt.registerSingleton<IErrorReporter>(reporter);

        final goesOn = handleCompositionReport(
          mismatch(flavor),
          isRelease: true,
        );
        await tester.pump();

        expect(goesOn, isFalse);
        expect(find.byType(BootErrorApp), findsOneWidget);
        expect(find.textContaining('[C02]'), findsOneWidget);
        expect(logged, isEmpty);
        expect(reporter.recorded, isEmpty);
      });
    }

    testWidgets('a debug or profile build of the prod flavor stops too', (
      tester,
    ) async {
      final goesOn = handleCompositionReport(
        mismatch(Flavor.prod),
        isRelease: false,
      );
      await tester.pump();

      expect(goesOn, isFalse);
      expect(find.byType(BootErrorApp), findsOneWidget);
      expect(find.textContaining('`capabilities.splash`'), findsOneWidget);
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
      expect(getIt.isRegistered<ShellHooks>(), isFalse);
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
