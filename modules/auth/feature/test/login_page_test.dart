import 'package:core_base_ui/core_base_ui.dart';
import 'package:core_di/core_di.dart';
import 'package:core_responsive/core_responsive.dart';
import 'package:domain_auth/domain_auth.dart';
import 'package:domain_core/domain_core.dart';
import 'package:feature_auth/feature_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider_state_management/provider_state_management.dart';

import 'auth_fakes.dart';

class _LightThemeStorage implements IThemeStorage {
  @override
  ThemeMode getThemeMode() => ThemeMode.light;

  @override
  void saveThemeMode(ThemeMode mode) {}
}

/// The login screen on the smallest phone window at the largest text size the
/// shell allows (RULE-38): it must lay out without overflow, validate with
/// translated messages, and clear a rejected password.
void main() {
  late FakeAuthRepository repository;

  setUp(() => repository = FakeAuthRepository());

  Future<void> pumpLogin(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(320, 568)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final stream = AuthStatusStreamImpl();
    final auth = AuthProvider(LoginUseCase(repository), repository, stream);
    final theme = ThemeProvider(_LightThemeStorage());
    addTearDown(auth.dispose);
    addTearDown(stream.dispose);
    addTearDown(theme.dispose);
    await tester.pumpWidget(
      ResponsiveInit(
        designSize: const Size(375, 812),
        splitScreenMode: true,
        child: Builder(
          builder: (context) => MaterialApp(
            theme: theme.lightTheme(context),
            localizationsDelegates: [
              ...FeatureAuthLocalizations.localizationsDelegates,
              ...AppLocalizations.localizationsDelegates,
            ],
            supportedLocales: FeatureAuthLocalizations.supportedLocales,
            home: ChangeNotifierProvider<AuthProvider>.value(
              value: auth,
              child: const LoginPage(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  FeatureAuthLocalizations l10nOf(WidgetTester tester) =>
      FeatureAuthLocalizations.of(tester.element(find.byType(LoginPage)))!;

  Future<void> submit(
    WidgetTester tester,
    String email,
    String password,
  ) async {
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.first, email);
    await tester.enterText(fields.last, password);
    final button = find.text(l10nOf(tester).signIn);
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  testWidgets('an empty form asks for both fields and signs nobody in', (
    tester,
  ) async {
    await pumpLogin(tester);

    await submit(tester, '', '');

    expect(find.text(l10nOf(tester).fieldRequired), findsNWidgets(2));
    expect(repository.logins, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a rejected password is cleared; the email is sent trimmed', (
    tester,
  ) async {
    repository.loginResult = const Result.failure(
      AuthFailure(message: 'Unauthorized', code: 401),
    );
    await pumpLogin(tester);

    await submit(tester, ' ada@example.com ', 'wrong-password');

    expect(repository.logins, [
      const LoginParams(email: 'ada@example.com', password: 'wrong-password'),
    ]);
    expect(find.text(' ada@example.com '), findsOneWidget);
    expect(find.text('wrong-password'), findsNothing);
  });
}
