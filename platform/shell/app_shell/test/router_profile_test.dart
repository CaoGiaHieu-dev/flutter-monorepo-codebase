import 'dart:async';

import 'package:core_common/core_common.dart';
import 'package:core_di/core_di.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:platform_app_shell/platform_app_shell.dart';
import 'package:platform_shell_adapters/platform_shell_adapters.dart';

import 'support/profile_fakes.dart';
import 'support/shell_fakes.dart';

/// K9 and the router hooks — what an app says about the router
/// (`RouterProfile`, `ShellHooks.navigatorObservers`, `ShellHooks.redirect`)
/// reaches `AppRouter`. The defaults are what the router always did: the entry
/// location on the first launch only, the first tab as the fallback, one
/// observer and no guard.
void main() {
  setUp(getIt.enableRegisteringMultipleInstancesOfOneType);
  tearDown(getIt.reset);

  AppRouter registerShell(
    RouterProfile? profile, {
    AppBootStorage? boot,
    String postSignIn = '/home',
  }) {
    final router = profile == null ? AppRouter() : AppRouter(profile);
    getIt
      ..registerSingleton<AppRouter>(router)
      ..registerSingleton<DeeplinkProvider>(FakeDeeplinkProvider(router))
      ..registerSingleton<IPostSignInLocation>(
        FakePostSignInLocation(postSignIn),
      );
    if (boot != null) getIt.registerSingleton<AppBootStorage>(boot);
    return router;
  }

  FakeDestination homeTab() => FakeDestination(
    path: '/home',
    routes: [GoRoute(path: '/home', builder: (_, _) => const Text('home'))],
  );

  void registerOnboarding() {
    getIt
      ..registerSingleton<IAppEntryLocation>(FakeEntryLocation('/onboarding'))
      ..registerSingleton<IFeatureRouteModule>(
        FakeFeatureRoutes([
          GoRoute(
            path: '/onboarding',
            builder: (_, _) => const Text('onboarding'),
          ),
        ]),
      )
      ..registerSingleton<INavDestinationModule>(homeTab());
  }

  Future<void> pump(WidgetTester tester, AppRouter router) async {
    await tester.pumpWidget(MaterialApp.router(routerConfig: router.router));
    await tester.pumpAndSettle();
  }

  String location(AppRouter router) =>
      router.router.routerDelegate.currentConfiguration.uri.toString();

  group('RouterProfile.fallbackPath', () {
    test('the default is the first destination, else the placeholder', () {
      final empty = AppRouter();
      expect(empty.fallbackLocation, '/_empty_dashboard');

      getIt.registerSingleton<INavDestinationModule>(homeTab());
      expect(AppRouter().fallbackLocation, '/home');
    });

    test('an app path replaces both', () {
      const profile = RouterProfile(fallbackPath: '/start');
      expect(AppRouter(profile).fallbackLocation, '/start');

      getIt.registerSingleton<INavDestinationModule>(homeTab());
      expect(AppRouter(profile).fallbackLocation, '/start');
    });

    test('it is the cold-start location once the entry has been seen', () {
      registerOnboarding();
      getIt.registerSingleton<AppBootStorage>(
        memoryBootStorage(viewedOnboard: true),
      );

      expect(
        AppRouter(const RouterProfile(fallbackPath: '/start')).entryLocation,
        '/start',
      );
    });
  });

  group('RouterProfile.entry', () {
    test('firstLaunch, the default: the entry location until it is seen', () {
      registerOnboarding();
      getIt.registerSingleton<AppBootStorage>(memoryBootStorage());

      expect(AppRouter().entryLocation, '/onboarding');
      expect(
        AppRouter(const RouterProfile()).entryLocation,
        '/onboarding',
      );
    });

    test('firstLaunch: the fallback once it has been seen', () async {
      registerOnboarding();
      getIt.registerSingleton<AppBootStorage>(
        memoryBootStorage(viewedOnboard: true),
      );

      expect(AppRouter().entryLocation, '/home');
    });

    test('always: the entry location on every cold start', () {
      registerOnboarding();
      getIt.registerSingleton<AppBootStorage>(
        memoryBootStorage(viewedOnboard: true),
      );

      expect(
        AppRouter(const RouterProfile(entry: EntryPolicy.always)).entryLocation,
        '/onboarding',
      );
    });

    test('never: the fallback, whatever is registered and seen', () {
      registerOnboarding();
      getIt.registerSingleton<AppBootStorage>(memoryBootStorage());
      const profile = RouterProfile(entry: EntryPolicy.never);

      expect(AppRouter(profile).entryLocation, '/home');
      expect(AppRouter(profile).usesEntryLocation, isFalse);
      expect(AppRouter().usesEntryLocation, isTrue);
    });

    testWidgets('never: boot opens the first tab and does not consume '
        'the first-launch flag', (tester) async {
      final router = registerShell(
        const RouterProfile(entry: EntryPolicy.never),
        boot: memoryBootStorage(),
      );
      registerOnboarding();

      await pump(tester, router);

      expect(location(router), '/home');
      expect(find.text('onboarding'), findsNothing);
      expect(getIt<AppBootStorage>().viewedOnboard, isFalse);
    });

    testWidgets('always: a returning user still opens on the entry location', (
      tester,
    ) async {
      final router = registerShell(
        const RouterProfile(entry: EntryPolicy.always),
        boot: memoryBootStorage(viewedOnboard: true),
        // Where boot sends a user who is not on the entry location.
        postSignIn: '/onboarding',
      );
      registerOnboarding();

      await pump(tester, router);

      expect(location(router), '/onboarding');
    });
  });

  group('ShellHooks.navigatorObservers', () {
    final runtime = AppRuntime(
      profile: testProfile(),
      flavor: Flavor.dev,
      platform: AppPlatform.android,
      isDebug: true,
    );

    testWidgets('an app observer sees navigation beside the shell\'s', (
      tester,
    ) async {
      final observer = _CountingObserver();
      AppRuntime? seenRuntime;
      getIt
        ..registerSingleton<AppRuntime>(runtime)
        ..registerSingleton<ShellHooks>(
          ShellHooks(
            navigatorObservers: (rt) {
              seenRuntime = rt;
              return [observer];
            },
          ),
        );
      final router = registerShell(null, postSignIn: '/a');
      getIt.registerSingleton<IFeatureRouteModule>(
        FakeFeatureRoutes([
          GoRoute(path: '/a', builder: (_, _) => const Text('a')),
          GoRoute(path: '/b', builder: (_, _) => const Text('b')),
        ]),
      );
      router.router.go('/a');
      await pump(tester, router);
      observer.pushes = 0;

      unawaited(router.router.push('/b'));
      await tester.pumpAndSettle();

      expect(observer.pushes, 1);
      expect(seenRuntime, same(runtime));
      expect(router.router.configuration.navigatorKey, isNotNull);
    });

    testWidgets('no hook: only the shell\'s own observer', (tester) async {
      final router = registerShell(null, postSignIn: '/a');
      getIt.registerSingleton<IFeatureRouteModule>(
        FakeFeatureRoutes([
          GoRoute(path: '/a', builder: (_, _) => const Text('a')),
        ]),
      );
      router.router.go('/a');

      await pump(tester, router);

      expect(location(router), '/a');
    });

    testWidgets('a hook with no registered runtime is never called', (
      tester,
    ) async {
      var called = false;
      getIt.registerSingleton<ShellHooks>(
        ShellHooks(
          navigatorObservers: (_) {
            called = true;
            return const [];
          },
        ),
      );
      final router = registerShell(null, postSignIn: '/a');
      getIt.registerSingleton<IFeatureRouteModule>(
        FakeFeatureRoutes([
          GoRoute(path: '/a', builder: (_, _) => const Text('a')),
        ]),
      );
      router.router.go('/a');

      await pump(tester, router);

      expect(called, isFalse);
    });
  });

  group('ShellHooks.redirect', () {
    testWidgets('one app-wide guard runs on every navigation', (tester) async {
      final seen = <String>[];
      getIt.registerSingleton<ShellHooks>(
        ShellHooks(
          redirect: (context, state) {
            seen.add(state.uri.path);
            return state.uri.path == '/blocked' ? '/a' : null;
          },
        ),
      );
      final router = registerShell(null, postSignIn: '/a');
      getIt.registerSingleton<IFeatureRouteModule>(
        FakeFeatureRoutes([
          GoRoute(path: '/a', builder: (_, _) => const Text('a')),
          GoRoute(path: '/blocked', builder: (_, _) => const Text('blocked')),
        ]),
      );
      router.router.go('/a');
      await pump(tester, router);
      expect(location(router), '/a');

      router.router.go('/blocked');
      await tester.pumpAndSettle();

      expect(location(router), '/a');
      expect(find.text('blocked'), findsNothing);
      expect(seen, contains('/blocked'));
    });

    testWidgets('no hook: navigation goes through', (tester) async {
      final router = registerShell(null, postSignIn: '/a');
      getIt.registerSingleton<IFeatureRouteModule>(
        FakeFeatureRoutes([
          GoRoute(path: '/a', builder: (_, _) => const Text('a')),
          GoRoute(path: '/blocked', builder: (_, _) => const Text('blocked')),
        ]),
      );
      router.router.go('/a');
      await pump(tester, router);

      router.router.go('/blocked');
      await tester.pumpAndSettle();

      expect(location(router), '/blocked');
    });
  });
}

class _CountingObserver extends NavigatorObserver {
  int pushes = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => pushes++;
}
