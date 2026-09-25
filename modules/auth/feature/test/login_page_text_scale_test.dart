import 'package:core_base_ui/core_base_ui.dart';
import 'package:core_di/core_di.dart';
import 'package:core_responsive/core_responsive.dart';
import 'package:domain_auth/domain_auth.dart';
import 'package:domain_core/domain_core.dart';
import 'package:feature_auth/feature_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// The app honours the OS font size up to 2x (`RootApp` clamps it with
/// `MediaQuery.withClampedTextScaling`). The login screen must lay out at
/// that cap on a phone — no RenderFlex overflow, no clipped field — with
/// and without the validation errors under the fields.
const _maxTextScale = 2.0;

class _SignedOutRepository implements IAuthRepository {
  @override
  Future<Result<UserEntity>> login(LoginParams params) async =>
      const Result.failure(AuthFailure(message: 'nope', code: 401));

  @override
  Future<Result<void>> logout() async => const Result.success(null);

  @override
  Future<Result<UserEntity>> refreshToken() => restoreSession();

  @override
  Future<Result<UserEntity>> restoreSession() async =>
      const Result.failure(AuthFailure(message: 'no session', code: 401));
}

class _LightThemeStorage implements IThemeStorage {
  @override
  ThemeMode getThemeMode() => ThemeMode.light;

  @override
  void saveThemeMode(ThemeMode mode) {}
}

AuthProvider _authProvider() {
  final repository = _SignedOutRepository();
  return AuthProvider(
    LoginUseCase(repository),
    LogoutUseCase(repository),
    RestoreSessionUseCase(repository),
    AuthStatusStreamImpl(),
  );
}

Future<void> _pumpLogin(WidgetTester tester, Size window) async {
  tester.view
    ..physicalSize = window
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.textScaleFactorTestValue = _maxTextScale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

  final auth = _authProvider();
  final theme = ThemeProvider(_LightThemeStorage());
  await tester.pumpWidget(
    // The app's artboard and default bounds — see `MainScope`.
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

void main() {
  for (final window in const [Size(320, 568), Size(360, 640), Size(375, 812)]) {
    testWidgets('lays out at ${_maxTextScale}x text on a $window phone', (
      tester,
    ) async {
      await _pumpLogin(tester, window);

      final scaler = MediaQuery.textScalerOf(
        tester.element(find.byType(LoginPage)),
      );
      expect(scaler.scale(10), 10 * _maxTextScale);
      expect(find.byType(TextFormField), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'validation errors at ${_maxTextScale}x text on a $window phone',
      (tester) async {
        await _pumpLogin(tester, window);

        final submit = find.text('Sign In').last;
        await tester.ensureVisible(submit);
        await tester.tap(submit);
        await tester.pumpAndSettle();

        expect(find.text('Email is required'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('a rejected password is cleared for the next attempt', (
    tester,
  ) async {
    await _pumpLogin(tester, const Size(375, 812));

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.first, 'ada@example.com');
    await tester.enterText(fields.last, 'wrong-password');
    final submit = find.text('Sign In').last;
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(find.text('ada@example.com'), findsOneWidget);
    expect(find.text('wrong-password'), findsNothing);
  });
}
