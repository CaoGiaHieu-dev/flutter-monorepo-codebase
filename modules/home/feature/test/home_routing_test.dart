import 'package:core_base_ui/core_base_ui.dart';
import 'package:core_common/core_common.dart';
import 'package:core_di/core_di.dart';
import 'package:core_responsive/core_responsive.dart';
import 'package:feature_home/feature_home.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

class _FakeAuthStatusStream implements ISessionStatusStream {
  @override
  SessionPrincipal? get currentUser => const SessionPrincipal(
    id: '1',
    displayName: 'Ada',
  );

  @override
  Stream<SessionPrincipal?> get sessionStatusStream => const Stream.empty();
}

class _LightThemeStorage implements IThemeStorage {
  @override
  ThemeMode getThemeMode() => ThemeMode.light;

  @override
  void saveThemeMode(ThemeMode mode) {}
}

void main() {
  tearDown(getIt.reset);

  test('every home entry point agrees on the one home path', () {
    expect(const HomeRoute().location, HomePath.HOME);
    expect(HomeNavDestination().path, HomePath.HOME);
    expect(HomePostSignInLocation().path, HomePath.HOME);
  });

  test('the home tab is the first destination and contributes its route', () {
    final destination = HomeNavDestination();

    expect(destination.order, 0);
    expect(destination.routes, hasLength(1));
  });

  /// Pumps a router whose only other page holds [launcher], with the home
  /// destination's own routes behind it.
  Future<GoRouter> pumpRouter(
    WidgetTester tester, {
    required Widget Function(BuildContext) launcher,
  }) async {
    final theme = ThemeProvider(_LightThemeStorage());
    addTearDown(theme.dispose);
    final router = GoRouter(
      initialLocation: '/start',
      routes: [
        GoRoute(path: '/start', builder: (context, _) => launcher(context)),
        ...HomeNavDestination().routes,
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ResponsiveInit(
        child: Builder(
          builder: (context) => MaterialApp.router(
            routerConfig: router,
            theme: theme.lightTheme(context),
            localizationsDelegates: [
              ...FeatureHomeLocalizations.localizationsDelegates,
              ...AppLocalizations.localizationsDelegates,
            ],
            supportedLocales: FeatureHomeLocalizations.supportedLocales,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return router;
  }

  testWidgets('HomeNavigatorImpl.toHome opens the home page', (tester) async {
    // Home's route creates its bloc through DI, as the app does.
    getIt.registerFactoryParam<HomeProfileBloc, ISessionStatusStream?, void>(
      (stream, _) => HomeProfileBloc(stream),
    );
    await pumpRouter(
      tester,
      launcher: (context) => TextButton(
        onPressed: () => HomeNavigatorImpl().toHome(context),
        child: const Text('go'),
      ),
    );
    expect(find.byType(HomePage), findsNothing);

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(find.byType(HomePage), findsOneWidget);
  });

  testWidgets('the route hands the bloc the session stream when one exists', (
    tester,
  ) async {
    getIt
      ..registerSingleton<ISessionStatusStream>(_FakeAuthStatusStream())
      ..registerFactoryParam<HomeProfileBloc, ISessionStatusStream?, void>(
        (stream, _) => HomeProfileBloc(stream),
      );
    final router = await pumpRouter(
      tester,
      launcher: (_) => const SizedBox.shrink(),
    );

    router.go(HomePath.HOME);
    await tester.pumpAndSettle();

    expect(find.text('Ada'), findsOneWidget);
  });

  testWidgets('without an auth module the route still builds, signed out', (
    tester,
  ) async {
    getIt.registerFactoryParam<HomeProfileBloc, ISessionStatusStream?, void>(
      (stream, _) => HomeProfileBloc(stream),
    );
    final router = await pumpRouter(
      tester,
      launcher: (_) => const SizedBox.shrink(),
    );

    router.go(HomePath.HOME);
    await tester.pumpAndSettle();

    final l10n = FeatureHomeLocalizations.of(
      tester.element(find.byType(HomePage)),
    )!;
    expect(find.text(l10n.userLoggedOut), findsOneWidget);
  });
}
