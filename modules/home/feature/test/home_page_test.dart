import 'package:core_base_ui/core_base_ui.dart';
import 'package:core_common/core_common.dart';
import 'package:core_di/core_di.dart';
import 'package:core_responsive/core_responsive.dart';
import 'package:feature_home/feature_home.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

class _FakeSessionStream implements ISessionStatusStream {
  @override
  SessionPrincipal? get currentUser =>
      const SessionPrincipal(id: '1', displayName: 'Ada');

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
  setUp(() {
    // The route creates its bloc through DI, as the app does.
    getIt.registerFactoryParam<HomeProfileBloc, ISessionStatusStream?, void>(
      (stream, _) => HomeProfileBloc(stream),
    );
  });
  tearDown(getIt.reset);

  /// Pumps a router with a `/start` page holding [launcher] and Home's routes.
  Future<void> pumpRouter(
    WidgetTester tester, {
    Widget Function(BuildContext)? launcher,
  }) async {
    final theme = ThemeProvider(_LightThemeStorage());
    addTearDown(theme.dispose);
    final router = GoRouter(
      initialLocation: launcher == null ? HomePath.HOME : '/start',
      routes: [
        GoRoute(
          path: '/start',
          builder: (context, _) => launcher!(context),
        ),
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
  }

  FeatureHomeLocalizations l10nOf(WidgetTester tester) =>
      FeatureHomeLocalizations.of(tester.element(find.byType(HomePage)))!;

  testWidgets('without an auth module the route builds, signed out', (
    tester,
  ) async {
    await pumpRouter(tester);

    expect(find.text(l10nOf(tester).userLoggedOut), findsOneWidget);
  });

  testWidgets('with an auth module the route hands the bloc its stream, and '
      'a 2x text size scrolls instead of overflowing', (tester) async {
    getIt.registerSingleton<ISessionStatusStream>(_FakeSessionStream());
    tester.view
      ..physicalSize = const Size(320, 200)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await pumpRouter(tester);

    expect(tester.takeException(), isNull);
    expect(find.text(l10nOf(tester).userLoggedIn), findsOneWidget);
    expect(find.text('Ada'), findsOneWidget);
  });

  testWidgets('HomeNavigatorImpl.toHome opens the home page', (tester) async {
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
    expect(HomePostSignInLocation().path, const HomeRoute().location);
  });
}
