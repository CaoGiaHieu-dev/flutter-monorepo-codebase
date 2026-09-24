import 'package:core_common/core_common.dart';
import 'package:core_di/core_di.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:platform_app_shell/platform_app_shell.dart';
import 'package:platform_shell_adapters/platform_shell_adapters.dart';

import 'support/shell_fakes.dart';

class _SignedOut implements IAuthSessionState {
  @override
  AuthPrincipal? get signedInUser => null;

  @override
  bool get hasRestoredSession => true;

  @override
  Future<void> ensureInitialized() async {}

  @override
  Stream<AuthPrincipal?> get sessionChanges => const Stream.empty();

  @override
  Stream<AuthSessionFailure> get sessionFailures => const Stream.empty();

  @override
  void onSessionLost() {}
}

class _LoginNavigator implements AuthNavigator {
  int calls = 0;

  @override
  void toLogin(BuildContext context) {
    calls++;
    context.go('/login');
  }
}

/// A shell with onboarding (the entry location), a login route and one
/// destination; auth is composed only when [session] is given.
Future<(AppRouter, FakeDeeplinkProvider)> _boot(
  WidgetTester tester, {
  required bool viewedOnboard,
  IAuthSessionState? session,
  AuthNavigator? authNavigator,
}) async {
  final router = AppRouter();
  final deeplinks = FakeDeeplinkProvider(router);
  getIt
    ..registerSingleton<AppRouter>(router)
    ..registerSingleton<DeeplinkProvider>(deeplinks)
    ..registerSingleton<AppBootStorage>(
      memoryBootStorage(viewedOnboard: viewedOnboard),
    )
    ..registerSingleton<IAppEntryLocation>(FakeEntryLocation('/onboarding'))
    ..registerSingleton<IFeatureRouteModule>(
      FakeFeatureRoutes([
        GoRoute(
          path: '/onboarding',
          builder: (_, _) => const Text('onboarding'),
        ),
        GoRoute(path: '/login', builder: (_, _) => const Text('login')),
      ]),
    )
    ..registerSingleton<INavDestinationModule>(
      FakeDestination(
        path: '/home',
        routes: [GoRoute(path: '/home', builder: (_, _) => const Text('home'))],
      ),
    );
  if (session != null) getIt.registerSingleton<IAuthSessionState>(session);
  if (authNavigator != null) {
    getIt.registerSingleton<AuthNavigator>(authNavigator);
  }

  await tester.pumpWidget(MaterialApp.router(routerConfig: router.router));
  await tester.pumpAndSettle();
  return (router, deeplinks);
}

String _location(AppRouter router) =>
    router.router.routerDelegate.currentConfiguration.uri.toString();

void main() {
  tearDown(getIt.reset);

  group('deep links in a build without auth', () {
    testWidgets('start when the user leaves onboarding, not before', (
      tester,
    ) async {
      final (router, deeplinks) = await _boot(tester, viewedOnboard: false);

      expect(_location(router), '/onboarding');
      expect(deeplinks.initCalls, 0, reason: 'never routed over onboarding');

      router.router.go('/home');
      await tester.pumpAndSettle();
      expect(deeplinks.initCalls, 1);

      // Started once; later navigation does not restart them.
      router.router.go('/onboarding');
      await tester.pumpAndSettle();
      router.router.go('/home');
      await tester.pumpAndSettle();
      expect(deeplinks.initCalls, 1);
    });

    testWidgets('start at boot for a returning user', (tester) async {
      final (router, deeplinks) = await _boot(tester, viewedOnboard: true);

      expect(_location(router), '/home');
      expect(deeplinks.initCalls, 1);
    });
  });

  group('with auth composed', () {
    testWidgets('leaving onboarding for login does not start deep links', (
      tester,
    ) async {
      final login = _LoginNavigator();
      final (router, deeplinks) = await _boot(
        tester,
        viewedOnboard: false,
        session: _SignedOut(),
        authNavigator: login,
      );
      expect(_location(router), '/onboarding');

      login.toLogin(tester.element(find.text('onboarding')));
      await tester.pumpAndSettle();

      expect(_location(router), '/login');
      expect(deeplinks.initCalls, 0);
    });

    testWidgets(
      'a signed-out returning user is sent to login, not onboarding',
      (
        tester,
      ) async {
        final login = _LoginNavigator();
        final (router, deeplinks) = await _boot(
          tester,
          viewedOnboard: true,
          session: _SignedOut(),
          authNavigator: login,
        );

        expect(login.calls, 1);
        expect(_location(router), '/login');
        expect(deeplinks.initCalls, 0);
      },
    );
  });
}
