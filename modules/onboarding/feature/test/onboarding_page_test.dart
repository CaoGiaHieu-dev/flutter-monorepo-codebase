import 'package:core_common/core_common.dart';
import 'package:core_di/core_di.dart';
import 'package:core_responsive/core_responsive.dart';
import 'package:feature_onboarding/feature_onboarding.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

class _Tab extends INavDestinationModule {
  _Tab(this.order, this.path);

  @override
  final int order;

  @override
  final String path;

  @override
  List<RouteBase> get routes => const [];

  @override
  NavDestination destination(BuildContext context) =>
      NavDestination(label: path, icon: Icons.circle);
}

class _Home implements HomeNavigator {
  int calls = 0;

  @override
  void toHome(BuildContext context) => calls++;
}

/// "Get started" reaches auth, else home — and with neither composed it does
/// nothing rather than hardcoding a route.
void main() {
  tearDown(getIt.reset);

  Future<GoRouter> pumpOnboarding(WidgetTester tester) async {
    final router = GoRouter(
      initialLocation: '/onboarding',
      routes: [
        GoRoute(
          path: '/onboarding',
          builder: (_, _) => const OnboardingPage(),
        ),
        for (final path in ['/first', '/second'])
          GoRoute(path: path, builder: (_, _) => Text('at $path')),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        localizationsDelegates:
            FeatureOnboardingLocalizations.localizationsDelegates,
        supportedLocales: FeatureOnboardingLocalizations.supportedLocales,
        builder: (context, child) => ResponsiveInit(child: child!),
      ),
    );
    await tester.pumpAndSettle();
    return router;
  }

  testWidgets('prefers the home module when one is composed', (tester) async {
    final home = _Home();
    getIt
      ..registerSingleton<HomeNavigator>(home)
      ..registerSingleton<INavDestinationModule>(_Tab(0, '/first'));
    await pumpOnboarding(tester);

    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();

    expect(home.calls, 1);
    expect(find.text('at /first'), findsNothing);
  });

  testWidgets('with neither auth nor home, stays put', (tester) async {
    await pumpOnboarding(tester);

    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();

    expect(find.byType(OnboardingPage), findsOneWidget);
  });
}
