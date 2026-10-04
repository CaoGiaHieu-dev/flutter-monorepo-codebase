import 'package:core_di/core_di.dart';
import 'package:core_responsive/core_responsive.dart';
import 'package:feature_onboarding/feature_onboarding.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// Onboarding is the first-launch screen: the shell sends a fresh install to
/// `IAppEntryLocation.path`, so that path must be one the module's own route
/// answers, outside the tabbed dashboard.
void main() {
  test('the entry location is the onboarding route', () {
    expect(OnboardingAppEntryLocation().path, OnboardingPath.ONBOARDING);
    expect(const OnboardingRoute().location, OnboardingPath.ONBOARDING);
  });

  test('the module contributes one stack route, on the app navigator', () {
    final routes = OnboardingFeatureRouteModule().routes;

    expect(routes, hasLength(1));
    final route = routes.single as GoRoute;
    expect(route.path, OnboardingPath.ONBOARDING);
    // Not inside the dashboard shell: no tab bar around a first launch.
    expect(route.parentNavigatorKey, NavigatorKeys.appKey);
  });

  testWidgets('a fresh launch at the entry location shows the welcome page', (
    tester,
  ) async {
    final router = GoRouter(
      navigatorKey: NavigatorKeys.appKey,
      initialLocation: OnboardingAppEntryLocation().path,
      routes: OnboardingFeatureRouteModule().routes,
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ResponsiveInit(
        child: MaterialApp.router(
          routerConfig: router,
          localizationsDelegates:
              FeatureOnboardingLocalizations.localizationsDelegates,
          supportedLocales: FeatureOnboardingLocalizations.supportedLocales,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final l10n = FeatureOnboardingLocalizations.of(
      tester.element(find.byType(OnboardingPage)),
    )!;
    expect(find.text(l10n.welcomeToOnboarding), findsOneWidget);
    expect(find.text(l10n.getStarted), findsOneWidget);
  });
}
