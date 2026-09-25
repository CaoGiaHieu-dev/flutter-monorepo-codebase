import 'package:auth_api/auth_api.dart';
import 'package:core_common/core_common.dart';
import 'package:core_responsive/core_responsive.dart';
import 'package:feature_onboarding/feature_onboarding.dart';
import 'package:flutter_test/flutter_test.dart';
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

/// "Get started" goes to sign-in when the auth module is composed, to home
/// when only home is, and does nothing when neither is — it never hardcodes
/// a route.
void main() {
  tearDown(getIt.reset);

  Future<void> tapGetStarted(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates:
            FeatureOnboardingLocalizations.localizationsDelegates,
        supportedLocales: FeatureOnboardingLocalizations.supportedLocales,
        builder: (context, child) => ResponsiveInit(child: child!),
        home: const OnboardingPage(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();
  }

  testWidgets('with auth and home composed, sign-in wins', (tester) async {
    final auth = _Auth();
    final home = _Home();
    getIt
      ..registerSingleton<AuthNavigator>(auth)
      ..registerSingleton<HomeNavigator>(home);

    await tapGetStarted(tester);

    expect(auth.calls, 1);
    expect(home.calls, 0);
  });

  testWidgets('without auth, falls back to home', (tester) async {
    final home = _Home();
    getIt.registerSingleton<HomeNavigator>(home);

    await tapGetStarted(tester);

    expect(home.calls, 1);
  });

  testWidgets('with neither auth nor home, stays put', (tester) async {
    await tapGetStarted(tester);

    expect(find.byType(OnboardingPage), findsOneWidget);
  });
}
