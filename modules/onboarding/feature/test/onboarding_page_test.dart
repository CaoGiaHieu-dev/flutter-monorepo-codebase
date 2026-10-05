import 'package:auth_api/auth_api.dart';
import 'package:core_common/core_common.dart';
import 'package:core_di/core_di.dart';
import 'package:core_responsive/core_responsive.dart';
import 'package:feature_onboarding/feature_onboarding.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:home_api/home_api.dart';
import 'package:material_ui/material_ui.dart';

class _Auth implements AuthNavigator {
  int calls = 0;

  @override
  void toLogin(BuildContext context) => calls++;
}

class _Home implements HomeNavigator {
  int calls = 0;

  @override
  void toHome(BuildContext context) => calls++;
}

void main() {
  tearDown(getIt.reset);

  // The entry location is a path the module's own route answers.
  Future<void> pumpAtEntryLocation(WidgetTester tester) async {
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
  }

  testWidgets('the entry location shows the page; Get Started goes to sign-in '
      'when auth is composed', (tester) async {
    final auth = _Auth();
    final home = _Home();
    getIt
      ..registerSingleton<AuthNavigator>(auth)
      ..registerSingleton<HomeNavigator>(home);

    await pumpAtEntryLocation(tester);
    expect(find.byType(OnboardingPage), findsOneWidget);
    await tester.tap(find.byType(ElevatedButton));

    expect(auth.calls, 1);
    expect(home.calls, 0);
  });

  testWidgets('without auth, Get Started falls back to home', (tester) async {
    final home = _Home();
    getIt.registerSingleton<HomeNavigator>(home);

    await pumpAtEntryLocation(tester);
    await tester.tap(find.byType(ElevatedButton));

    expect(home.calls, 1);
  });
}
