import 'package:core_common/core_common.dart';
import 'package:core_di/core_di.dart';
import 'package:core_network/core_network.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:platform_app_shell/platform_app_shell.dart';

import 'support/profile_fakes.dart';
import 'support/shell_fakes.dart';

CompositionReport _check(AppProfile profile) => checkAppContract(
  profile,
  flavor: Flavor.dev,
  platform: AppPlatform.android,
);

List<String> _codes(CompositionReport report) =>
    report.problems.map((p) => p.code).toList();

ProfileProblem _problem(CompositionReport report, String code) =>
    report.problems.singleWhere((p) => p.code == code);

class _ExplodingTab extends FakeDestination {
  _ExplodingTab() : super(path: '/boom', routes: const []);

  @override
  List<RouteBase> get routes => throw StateError('tab routes are broken');
}

/// `checkAppContract` is what the DI smoke tests and the debug boot share:
/// the app's `capabilities:` declaration held against the graph it built,
/// plus the structural checks both smoke tests used to copy by hand.
void main() {
  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);
  setUp(getIt.enableRegisteringMultipleInstancesOfOneType);
  tearDown(() async {
    await getIt.reset();
    DioFailureClassifier.ensureRegistered();
  });

  group('a graph that matches its declaration', () {
    test('is clean, and says what it checked', () {
      registerRequiredShell();
      getIt.registerSingleton<IFeatureRouteModule>(aRoute());

      final report = _check(testProfile());

      expect(report.problems, isEmpty);
      expect(report.isClean, isTrue);
      expect(report.states, hasLength(kShellContracts.length));
      expect(report.explain(), contains('`test_app` on android, flavor dev'));
      expect(report.explain(), contains('22 contracts checked'));
    });

    test('lists every implementation of a collected contract', () {
      registerRequiredShell();
      getIt
        ..registerSingleton<IFeatureRouteModule>(aRoute('/a'))
        ..registerSingleton<IFeatureRouteModule>(aRoute('/b'));

      final routes = _check(
        testProfile(),
      ).states.singleWhere((s) => s.contract.id == 'routes');

      expect(routes.registered, hasLength(2));
      expect(routes.expectation, isA<ProvidedCapability>());
    });

    test('a required contract carries no declaration', () {
      registerRequiredShell();
      getIt.registerSingleton<IFeatureRouteModule>(aRoute());

      final storage = _check(
        testProfile(),
      ).states.singleWhere((s) => s.contract.id == 'language_storage');

      expect(storage.expectation, isNull);
      expect(storage.registered, hasLength(1));
    });

    test('with the splash and reporter provided and registered', () {
      registerRequiredShell();
      getIt
        ..registerSingleton<IFeatureRouteModule>(aRoute())
        ..registerSingleton<IAppSplashScreen>(FakeSplash())
        ..registerSingleton<IErrorReporter>(FakeReporter());

      final report = _check(
        testProfile(
          capabilities: declare(
            provided: const {'routes', 'splash', 'error_reporter'},
          ),
        ),
      );

      expect(report.problems, isEmpty);
    });
  });

  group('C01 required contract not registered', () {
    test('names the type, the id and what the shell does without it', () {
      registerRequiredShell(skip: const {'theme_storage'});
      getIt.registerSingleton<IFeatureRouteModule>(aRoute());

      final report = _check(testProfile());

      expect(_codes(report), ['C01']);
      final problem = _problem(report, 'C01');
      expect(problem.description, contains('IThemeStorage'));
      expect(problem.description, contains('theme_storage'));
      expect(problem.description, contains('boot throws'));
      expect(problem.action, contains('apps/test_app/app_manifest.yaml'));
    });

    test('every required row is held', () async {
      final required = kShellContracts
          .where((c) => c.need == ShellNeed.required)
          .map((c) => c.id)
          .toList();
      expect(required, hasLength(8));

      for (final id in required) {
        registerRequiredShell(skip: {id});
        getIt.registerSingleton<IFeatureRouteModule>(aRoute());

        final report = _check(testProfile());

        expect(
          report.problems.where((p) => p.code == 'C01'),
          hasLength(1),
          reason: id,
        );
        await getIt.reset();
        getIt.enableRegisteringMultipleInstancesOfOneType();
      }
    });
  });

  group('C02 declared provided, nothing registered', () {
    test('points at the manifest key and offers the absent form', () {
      registerRequiredShell();
      getIt.registerSingleton<IFeatureRouteModule>(aRoute());

      final report = _check(
        testProfile(
          capabilities: declare(provided: const {'routes', 'splash'}),
        ),
      );

      expect(_codes(report), ['C02']);
      final problem = _problem(report, 'C02');
      expect(problem.description, contains('`capabilities.splash`'));
      expect(problem.description, contains('IAppSplashScreen'));
      expect(problem.action, contains('splash: { state: absent, reason:'));
      expect(
        problem.action,
        contains('dart tools/composer/composer.dart sync --app test_app'),
      );
    });

    test('a bundle member is named by its bundle key', () {
      registerRequiredShell();
      getIt.registerSingleton<IFeatureRouteModule>(aRoute());

      final report = _check(
        testProfile(
          capabilities: declare(
            provided: const {
              'routes',
              'session_state',
              'session_gateway',
              'session_refresh',
              'sign_in',
            },
          ),
        ),
      );

      expect(_codes(report), ['C02', 'C02', 'C02', 'C02']);
      expect(
        report.problems.map((p) => p.description),
        everyElement(contains('`capabilities.session`')),
      );
    });
  });

  group('C03 declared absent, something registered', () {
    test('names what is registered and the reason that was given', () {
      registerRequiredShell();
      getIt
        ..registerSingleton<IFeatureRouteModule>(aRoute())
        ..registerSingleton<IErrorReporter>(FakeReporter());

      final report = _check(
        testProfile(
          capabilities: declare(
            provided: const {'routes'},
            overrides: const {
              'error_reporter': CapabilityExpectation.absent(
                'no crash backend chosen',
              ),
            },
          ),
        ),
      );

      expect(_codes(report), ['C03']);
      final problem = _problem(report, 'C03');
      expect(problem.description, contains('`capabilities.error_reporter`'));
      expect(problem.description, contains('no crash backend chosen'));
      expect(problem.description, contains('FakeReporter'));
      expect(problem.action, contains('error_reporter: provided'));
    });

    test('a collected contract with one implementation counts', () {
      registerRequiredShell();
      getIt
        ..registerSingleton<IFeatureRouteModule>(aRoute())
        ..registerSingleton<IAppTreeWrapper>(FakeTreeWrapper());

      final report = _check(testProfile());

      expect(_codes(report), ['C03']);
      expect(
        _problem(report, 'C03').description,
        contains('`capabilities.tree_wrappers`'),
      );
    });
  });

  group('C04 bundle members disagree', () {
    test('a bundle half provided, half absent', () {
      registerRequiredShell();
      getIt.registerSingleton<IFeatureRouteModule>(aRoute());

      final report = _check(
        testProfile(
          capabilities: declare(
            provided: const {'routes', 'session_state', 'sign_in'},
          ),
        ),
      );

      expect(_codes(report), contains('C04'));
      final problem = _problem(report, 'C04');
      expect(problem.description, contains('`session` bundle'));
      expect(problem.description, contains('session_state is provided'));
      expect(problem.description, contains('session_gateway is absent'));
      expect(problem.action, contains('session: provided'));
    });

    test('a bundle declared as one is not reported', () {
      registerRequiredShell();
      getIt.registerSingleton<IFeatureRouteModule>(aRoute());

      expect(_codes(_check(testProfile())), isNot(contains('C04')));
    });
  });

  group('C05 no route and no tab', () {
    test('an app with neither has no screen', () {
      registerRequiredShell();

      final report = _check(testProfile(capabilities: declare()));

      expect(_codes(report), ['C05']);
      expect(_problem(report, 'C05').description, contains('no screen'));
    });

    test('a tab alone is enough', () {
      registerRequiredShell();
      getIt.registerSingleton<INavDestinationModule>(
        FakeDestination(path: '/tab', routes: aRoute('/tab').routes),
      );

      expect(
        _check(testProfile(capabilities: declare(provided: const {'tabs'}))),
        isA<CompositionReport>().having((r) => r.problems, 'problems', isEmpty),
      );
    });
  });

  group('C06 duplicate INavDestinationModule.order', () {
    test('names the order that is shared (RULE-24)', () {
      registerRequiredShell();
      getIt
        ..registerSingleton<INavDestinationModule>(
          FakeDestination(path: '/a', routes: aRoute('/a').routes, order: 2),
        )
        ..registerSingleton<INavDestinationModule>(
          FakeDestination(path: '/b', routes: aRoute('/b').routes, order: 2),
        )
        ..registerSingleton<INavDestinationModule>(
          FakeDestination(path: '/c', routes: aRoute('/c').routes, order: 3),
        );

      final report = _check(
        testProfile(capabilities: declare(provided: const {'tabs'})),
      );

      expect(_codes(report), ['C06']);
      expect(_problem(report, 'C06').description, contains('2 is used by'));
      expect(_problem(report, 'C06').action, contains('RULE-24'));
    });

    test('distinct orders are fine', () {
      registerRequiredShell();
      getIt
        ..registerSingleton<INavDestinationModule>(
          FakeDestination(path: '/a', routes: aRoute('/a').routes, order: 0),
        )
        ..registerSingleton<INavDestinationModule>(
          FakeDestination(path: '/b', routes: aRoute('/b').routes, order: 1),
        );

      final report = _check(
        testProfile(capabilities: declare(provided: const {'tabs'})),
      );

      expect(report.problems, isEmpty);
    });
  });

  group('C07 the router does not assemble', () {
    test('a malformed route is reported with the error', () {
      registerRequiredShell();
      // Two routes with one `name`: GoRouter asserts while it is built.
      getIt.registerSingleton<IFeatureRouteModule>(
        FakeFeatureRoutes([
          GoRoute(path: '/a', name: 'same', builder: (_, _) => const Text('a')),
          GoRoute(path: '/b', name: 'same', builder: (_, _) => const Text('b')),
        ]),
      );

      final report = _check(testProfile());

      expect(_codes(report), ['C07']);
      expect(
        _problem(report, 'C07').description,
        allOf(
          contains('`AppRouter.router` failed to assemble'),
          contains('duplication fullpaths for name "same"'),
        ),
      );
    });

    test('a contribution that throws while the router reads it', () {
      registerRequiredShell();
      getIt.registerSingleton<INavDestinationModule>(_ExplodingTab());

      final report = _check(
        testProfile(capabilities: declare(provided: const {'tabs'})),
      );

      expect(_codes(report), ['C07']);
      expect(
        _problem(report, 'C07').description,
        contains('tab routes are broken'),
      );
    });

    test('is not reported when the router itself is missing (C01 is)', () {
      registerRequiredShell(skip: const {'app_router', 'deeplink_provider'});
      getIt.registerSingleton<IFeatureRouteModule>(aRoute());

      expect(_codes(_check(testProfile())), ['C01', 'C01']);
    });
  });

  group('C08 DioFailureClassifier', () {
    test('not hooked into ErrorHandler', () {
      registerRequiredShell();
      getIt.registerSingleton<IFeatureRouteModule>(aRoute());
      ErrorHandler.unregisterClassifier(const DioFailureClassifier());

      final report = _check(testProfile());

      expect(_codes(report), ['C08']);
      expect(_problem(report, 'C08').description, contains('0 times'));
      expect(_problem(report, 'C08').action, contains('core_network'));
    });
  });

  group('C09 optional contract with no declaration', () {
    test('names the key to declare', () {
      registerRequiredShell();
      getIt.registerSingleton<IFeatureRouteModule>(aRoute());

      final report = _check(
        testProfile(
          capabilities: declare(
            provided: const {'routes'},
            omit: const {'analytics'},
          ),
        ),
      );

      expect(_codes(report), ['C09']);
      final problem = _problem(report, 'C09');
      expect(problem.description, contains('`analytics`'));
      expect(problem.description, contains('IAnalytics'));
      expect(
        problem.action,
        allOf(
          contains('analytics: provided'),
          contains('dart tools/composer/composer.dart sync --app test_app'),
        ),
      );
    });

    test('an app that declares nothing gets one C09 per optional row', () {
      registerRequiredShell();
      getIt.registerSingleton<IFeatureRouteModule>(aRoute());

      final report = _check(
        testProfile(capabilities: const <String, CapabilityExpectation>{}),
      );

      expect(report.problems.where((p) => p.code == 'C09'), hasLength(14));
    });
  });

  group('explain', () {
    test('prints every problem with its code, Description and Action', () {
      registerRequiredShell(skip: const {'boot_storage'});

      final report = _check(testProfile(capabilities: declare()));
      final text = report.explain();

      expect(_codes(report), ['C01', 'C05']);
      expect(text, contains('2 composition problems'));
      expect(text, contains('[C01] Description:'));
      expect(text, contains('[C05] Description:'));
      expect(text, contains('Action:'));
    });
  });
}
