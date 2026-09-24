import 'dart:async';

import 'package:core_common/core_common.dart';
import 'package:core_di/core_di.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:platform_app_shell/platform_app_shell.dart';
import 'package:platform_shell_adapters/platform_shell_adapters.dart';

import 'support/shell_fakes.dart';

/// Registers what `NavigatorWrapperWidget` resolves, plus [AppRouter].
AppRouter _registerShell({AppBootStorage? boot}) {
  final router = AppRouter();
  getIt
    ..registerSingleton<AppRouter>(router)
    ..registerSingleton<DeeplinkProvider>(FakeDeeplinkProvider(router))
    ..registerSingleton<HomeNavigator>(NoopHomeNavigator());
  if (boot != null) getIt.registerSingleton<AppBootStorage>(boot);
  return router;
}

Future<void> _pump(WidgetTester tester, AppRouter router) async {
  await tester.pumpWidget(MaterialApp.router(routerConfig: router.router));
  await tester.pumpAndSettle();
}

String _location(AppRouter router) =>
    router.router.routerDelegate.currentConfiguration.uri.toString();

void main() {
  setUp(getIt.enableRegisteringMultipleInstancesOfOneType);
  tearDown(getIt.reset);

  group('AppRouter.resolveEntryLocation', () {
    test('no entry location: the fallback', () {
      expect(
        AppRouter.resolveEntryLocation(
          entryPath: null,
          entrySeen: false,
          fallback: '/home',
        ),
        '/home',
      );
    });

    test('first launch: the entry location', () {
      expect(
        AppRouter.resolveEntryLocation(
          entryPath: '/onboarding',
          entrySeen: false,
          fallback: '/home',
        ),
        '/onboarding',
      );
    });

    test('once seen: the fallback, not the entry location', () {
      expect(
        AppRouter.resolveEntryLocation(
          entryPath: '/onboarding',
          entrySeen: true,
          fallback: '/home',
        ),
        '/home',
      );
    });
  });

  group('AppRouter cold start', () {
    List<RouteBase> onboardingRoutes() => [
      GoRoute(path: '/onboarding', builder: (_, _) => const Text('onboarding')),
    ];

    FakeDestination homeTab() => FakeDestination(
      path: '/home',
      routes: [GoRoute(path: '/home', builder: (_, _) => const Text('home'))],
    );

    testWidgets('first launch starts on the entry location', (tester) async {
      final router = _registerShell(boot: memoryBootStorage());
      getIt
        ..registerSingleton<IAppEntryLocation>(FakeEntryLocation('/onboarding'))
        ..registerSingleton<IFeatureRouteModule>(
          FakeFeatureRoutes(onboardingRoutes()),
        )
        ..registerSingleton<INavDestinationModule>(homeTab());

      await _pump(tester, router);

      expect(_location(router), '/onboarding');
      expect(find.text('onboarding'), findsOneWidget);
      // Boot records the entry location as seen for the next cold start.
      expect(getIt<AppBootStorage>().viewedOnboard.value, isTrue);
    });

    testWidgets('a returning user starts on the first destination', (
      tester,
    ) async {
      final router = _registerShell(
        boot: memoryBootStorage(viewedOnboard: true),
      );
      getIt
        ..registerSingleton<IAppEntryLocation>(FakeEntryLocation('/onboarding'))
        ..registerSingleton<IFeatureRouteModule>(
          FakeFeatureRoutes(onboardingRoutes()),
        )
        ..registerSingleton<INavDestinationModule>(homeTab());

      expect(router.entryLocation, '/home');
      await _pump(tester, router);

      expect(_location(router), '/home');
      expect(find.text('onboarding'), findsNothing);
    });
  });

  group('AppRouter.routeObserver', () {
    testWidgets('reports pushes and pops on the app shell navigator', (
      tester,
    ) async {
      final log = <String>[];
      final router = _registerShell();
      getIt.registerSingleton<IFeatureRouteModule>(
        FakeFeatureRoutes([
          GoRoute(path: '/a', builder: (_, _) => RouteAwareProbe('a', log)),
          GoRoute(path: '/b', builder: (_, _) => RouteAwareProbe('b', log)),
        ]),
      );
      router.router.go('/a');
      await _pump(tester, router);
      log.clear();

      // push completes only when /b pops — pumping drives the navigation.
      unawaited(router.router.push('/b'));
      await tester.pumpAndSettle();
      expect(log, containsAllInOrder(['a.didPushNext', 'b.didPush']));

      log.clear();
      router.router.pop();
      await tester.pumpAndSettle();
      expect(log, contains('a.didPopNext'));
    });

    testWidgets('reports pushes and pops inside a destination branch', (
      tester,
    ) async {
      final log = <String>[];
      final router = _registerShell();
      getIt.registerSingleton<INavDestinationModule>(
        FakeDestination(
          path: '/tab',
          routes: [
            GoRoute(
              path: '/tab',
              builder: (_, _) => RouteAwareProbe('tab', log),
              routes: [
                GoRoute(
                  path: 'detail',
                  builder: (_, _) => RouteAwareProbe('detail', log),
                ),
              ],
            ),
          ],
        ),
      );
      await _pump(tester, router);
      expect(_location(router), '/tab');
      log.clear();

      router.router.go('/tab/detail');
      await tester.pumpAndSettle();
      expect(log, containsAllInOrder(['tab.didPushNext', 'detail.didPush']));

      log.clear();
      router.router.pop();
      await tester.pumpAndSettle();
      expect(log, contains('tab.didPopNext'));
    });
  });
}
