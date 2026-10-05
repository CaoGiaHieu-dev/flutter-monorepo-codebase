import 'dart:async';

import 'package:core_base_ui/core_base_ui.dart';
import 'package:core_common/core_common.dart';
import 'package:core_di/core_di.dart';
import 'package:core_responsive/core_responsive.dart';
import 'package:core_ui_kit/core_ui_kit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:platform_app_shell/platform_app_shell.dart';
import 'package:platform_shell_adapters/platform_shell_adapters.dart';

import 'support/shell_fakes.dart';

class _SignedOut implements ISessionState {
  @override
  SessionPrincipal? get signedInUser => null;

  @override
  bool get hasRestoredSession => true;

  @override
  Future<void> ensureInitialized() async {}

  @override
  Stream<SessionPrincipal?> get sessionChanges => const Stream.empty();

  @override
  Stream<SessionFailure> get sessionFailures => const Stream.empty();

  @override
  void onSessionLost() {}
}

/// A session whose transitions the test drives through [change].
class _Session implements ISessionState {
  _Session(this.signedInUser);

  final _changes = StreamController<SessionPrincipal?>.broadcast();
  final _failures = StreamController<SessionFailure>.broadcast();

  @override
  SessionPrincipal? signedInUser;

  void change(SessionPrincipal? user) {
    signedInUser = user;
    _changes.add(user);
  }

  void fail(SessionFailure failure) => _failures.add(failure);

  Future<void> dispose() async {
    await _changes.close();
    await _failures.close();
  }

  @override
  bool get hasRestoredSession => true;

  @override
  Future<void> ensureInitialized() async {}

  @override
  Stream<SessionPrincipal?> get sessionChanges => _changes.stream;

  @override
  Stream<SessionFailure> get sessionFailures => _failures.stream;

  @override
  void onSessionLost() {}
}

const _ada = SessionPrincipal(id: 'u1', displayName: 'Ada');

/// A shell with onboarding (the entry location), a login route, a landing
/// route and one destination; a session owner is composed only when
/// [session] is given, and contributes [signIn] as its sign-in location.
/// [postSignIn] is the landing module's contribution, when there is one.
Future<(AppRouter, FakeDeeplinkProvider)> _boot(
  WidgetTester tester, {
  required bool viewedOnboard,
  ISessionState? session,
  ISignInLocation? signIn,
  IPostSignInLocation? postSignIn,
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
        GoRoute(path: '/landing', builder: (_, _) => const Text('landing')),
      ]),
    )
    ..registerSingleton<INavDestinationModule>(
      FakeDestination(
        path: '/home',
        routes: [GoRoute(path: '/home', builder: (_, _) => const Text('home'))],
      ),
    );
  if (session != null) getIt.registerSingleton<ISessionState>(session);
  if (signIn != null) getIt.registerSingleton<ISignInLocation>(signIn);
  if (postSignIn != null) {
    getIt.registerSingleton<IPostSignInLocation>(postSignIn);
  }

  await tester.pumpWidget(
    ResponsiveInit(
      child: MaterialApp.router(
        routerConfig: router.router,
        theme: ThemeData(extensions: [ThemeSystemExtension.light]),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) =>
            Overlay.wrap(child: AppOverlayInitializer(child: child!)),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (router, deeplinks);
}

String _location(AppRouter router) =>
    router.router.routerDelegate.currentConfiguration.uri.toString();

void main() {
  tearDown(getIt.reset);

  group('deep links in a build without a session owner', () {
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

  group('with a session owner composed', () {
    testWidgets('leaving onboarding for login does not start deep links', (
      tester,
    ) async {
      final (router, deeplinks) = await _boot(
        tester,
        viewedOnboard: false,
        session: _SignedOut(),
        signIn: FakeSignInLocation('/login'),
      );
      expect(_location(router), '/onboarding');

      router.router.go('/login');
      await tester.pumpAndSettle();

      expect(_location(router), '/login');
      expect(deeplinks.initCalls, 0);
    });

    testWidgets(
      'a signed-out returning user is sent to login, not onboarding',
      (
        tester,
      ) async {
        final (router, deeplinks) = await _boot(
          tester,
          viewedOnboard: true,
          session: _SignedOut(),
          signIn: FakeSignInLocation('/login'),
        );

        expect(_location(router), '/login');
        expect(deeplinks.initCalls, 0);
      },
    );
  });
  group('session failures', () {
    testWidgets('an expired session is explained in a translated toast', (
      tester,
    ) async {
      final session = _Session(_ada);
      addTearDown(session.dispose);
      await _boot(
        tester,
        viewedOnboard: true,
        session: session,
        signIn: FakeSignInLocation('/login'),
        postSignIn: FakePostSignInLocation('/landing'),
      );

      session.fail(const SessionExpiredFailure());
      await tester.pump();
      await tester.pump();

      final l10n = AppLocalizations.of(
        tester.element(find.byType(NavigatorWrapperWidget)),
      )!;
      expect(find.text(l10n.sessionExpired), findsOneWidget);

      AppOverlay.removeToastOverlay();
      await tester.pumpAndSettle();
    });
  });

  group('session locations', () {
    testWidgets('a signed-in returning user lands on IPostSignInLocation', (
      tester,
    ) async {
      final session = _Session(_ada);
      addTearDown(session.dispose);
      final (router, deeplinks) = await _boot(
        tester,
        viewedOnboard: true,
        session: session,
        signIn: FakeSignInLocation('/login'),
        postSignIn: FakePostSignInLocation('/landing'),
      );

      expect(_location(router), '/landing');
      expect(deeplinks.initCalls, 1);
    });

    testWidgets('with no IPostSignInLocation, AppRouter.fallbackLocation', (
      tester,
    ) async {
      final session = _Session(_ada);
      addTearDown(session.dispose);
      final (router, _) = await _boot(
        tester,
        viewedOnboard: true,
        session: session,
        signIn: FakeSignInLocation('/login'),
      );

      expect(_location(router), router.fallbackLocation);
      expect(_location(router), '/home');
    });

    testWidgets('sign-in and sign-out follow the two locations', (
      tester,
    ) async {
      final session = _Session(null);
      addTearDown(session.dispose);
      final (router, _) = await _boot(
        tester,
        viewedOnboard: true,
        session: session,
        signIn: FakeSignInLocation('/login'),
        postSignIn: FakePostSignInLocation('/landing'),
      );
      expect(_location(router), '/login');

      session.change(_ada);
      await tester.pumpAndSettle();
      expect(_location(router), '/landing');

      session.change(null);
      await tester.pumpAndSettle();
      expect(_location(router), '/login');
    });

    testWidgets('with no ISignInLocation, a signed-out user is not moved', (
      tester,
    ) async {
      final session = _Session(_ada);
      addTearDown(session.dispose);
      final (router, _) = await _boot(
        tester,
        viewedOnboard: true,
        session: session,
        postSignIn: FakePostSignInLocation('/landing'),
      );
      expect(_location(router), '/landing');

      session.change(null);
      await tester.pumpAndSettle();
      expect(_location(router), '/landing');
    });
  });
}
