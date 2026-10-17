import 'dart:async';

import 'package:core_base_ui/core_base_ui.dart';
import 'package:core_common/core_common.dart';
import 'package:core_responsive/core_responsive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:platform_app_shell/platform_app_shell.dart';

/// `UndefinedRouteWidget` is the router's `errorPageBuilder`: a translated
/// "page not found" whose button goes back when there is somewhere to go back
/// to, and to the app's fallback location when there is not.
void main() {
  late AppRouter appRouter;
  late GoRouter router;

  setUp(() {
    getIt.enableRegisteringMultipleInstancesOfOneType();
    appRouter = AppRouter(const RouterProfile(fallbackPath: '/home'));
    getIt.registerSingleton<AppRouter>(appRouter);
    router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const Text('root')),
        GoRoute(path: '/home', builder: (_, _) => const Text('home')),
      ],
      errorPageBuilder: (context, state) =>
          NoTransitionPage(child: UndefinedRouteWidget(state: state)),
    );
  });

  tearDown(() async {
    router.dispose();
    await getIt.reset();
  });

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => ResponsiveInit(child: child!),
      ),
    );
    await tester.pumpAndSettle();
  }

  AppLocalizations l10nOf(WidgetTester tester) =>
      AppLocalizations.of(tester.element(find.byType(UndefinedRouteWidget)))!;

  String location() => router.routerDelegate.currentConfiguration.uri.path;

  testWidgets('shows the unknown location and the translated message', (
    tester,
  ) async {
    await pumpApp(tester);
    router.go('/missing');
    await tester.pumpAndSettle();

    expect(find.byType(UndefinedRouteWidget), findsOneWidget);
    expect(find.text('/missing'), findsOneWidget);
    expect(find.text(l10nOf(tester).pageNotFound), findsOneWidget);
  });

  testWidgets('with nothing to go back to: "go to home" opens the fallback', (
    tester,
  ) async {
    await pumpApp(tester);
    router.go('/missing');
    await tester.pumpAndSettle();

    final l10n = l10nOf(tester);
    expect(find.text(l10n.goToHome), findsOneWidget);
    expect(find.text(l10n.goBack), findsNothing);

    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();

    expect(location(), '/home');
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('with a page underneath: "go back" pops to it', (tester) async {
    await pumpApp(tester);
    unawaited(router.push('/missing'));
    await tester.pumpAndSettle();

    final l10n = l10nOf(tester);
    expect(find.text(l10n.goBack), findsOneWidget);
    expect(find.text(l10n.goToHome), findsNothing);

    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();

    expect(location(), '/');
    expect(find.text('root'), findsOneWidget);
  });
}
