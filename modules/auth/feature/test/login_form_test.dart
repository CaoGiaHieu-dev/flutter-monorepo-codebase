import 'dart:async';

import 'package:core_base_ui/core_base_ui.dart';
import 'package:core_di/core_di.dart';
import 'package:core_responsive/core_responsive.dart';
import 'package:domain_auth/domain_auth.dart';
import 'package:domain_core/domain_core.dart';
import 'package:feature_auth/feature_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

class _FakeAuthRepository implements IAuthRepository {
  final logins = <LoginParams>[];

  /// When set, `login` waits for it instead of answering at once.
  Future<Result<UserEntity>>? pendingLogin;

  @override
  Future<Result<UserEntity>> login(LoginParams params) async {
    logins.add(params);
    final pending = pendingLogin;
    if (pending != null) return pending;
    return const Result.success(UserEntity(id: '1', name: 'Ada'));
  }

  @override
  Future<Result<void>> logout() async => const Result.success();

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

/// The form is the only thing between a user's typing and the repository:
/// it must refuse bad input with the translated message, and pass good input
/// through untouched.
void main() {
  late _FakeAuthRepository repository;

  setUp(() => repository = _FakeAuthRepository());

  Future<void> pumpLogin(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(375, 812)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final auth = AuthProvider(
      LoginUseCase(repository),
      LogoutUseCase(repository),
      RestoreSessionUseCase(repository),
      AuthStatusStreamImpl(),
    );
    final theme = ThemeProvider(_LightThemeStorage());
    addTearDown(auth.dispose);
    addTearDown(theme.dispose);
    await tester.pumpWidget(
      ResponsiveInit(
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
    WidgetTester tester, {
    required String email,
    required String password,
  }) async {
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.first, email);
    await tester.enterText(fields.last, password);
    final button = find.text(l10nOf(tester).signIn).last;
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  testWidgets('an empty form asks for both fields and signs nobody in', (
    tester,
  ) async {
    await pumpLogin(tester);

    await submit(tester, email: '', password: '');

    final l10n = l10nOf(tester);
    expect(find.text(l10n.emailIsRequired), findsOneWidget);
    expect(find.text(l10n.passwordIsRequired), findsOneWidget);
    expect(repository.logins, isEmpty);
  });

  testWidgets('an email without a domain is refused', (tester) async {
    await pumpLogin(tester);

    await submit(tester, email: 'ada@example', password: 'secret1');

    expect(find.text(l10nOf(tester).invalidEmail), findsOneWidget);
    expect(repository.logins, isEmpty);
  });

  testWidgets('a short password is refused, a six character one is not', (
    tester,
  ) async {
    await pumpLogin(tester);

    await submit(tester, email: 'ada@example.com', password: '12345');
    expect(find.text(l10nOf(tester).passwordTooShort), findsOneWidget);
    expect(repository.logins, isEmpty);

    await submit(tester, email: 'ada@example.com', password: '123456');
    expect(find.text(l10nOf(tester).passwordTooShort), findsNothing);
    expect(repository.logins, hasLength(1));
  });

  testWidgets('valid input reaches the repository exactly as typed', (
    tester,
  ) async {
    await pumpLogin(tester);

    await submit(tester, email: 'ada@example.com', password: 'secret1');

    expect(repository.logins, [
      const LoginParams(email: 'ada@example.com', password: 'secret1'),
    ]);
  });

  testWidgets('the email is sent trimmed (a keyboard autocomplete leaves a '
      'trailing space), the password exactly as typed', (tester) async {
    await pumpLogin(tester);

    await submit(
      tester,
      email: '  ada@example.com ',
      password: ' secret1 ',
    );

    expect(repository.logins, [
      const LoginParams(email: 'ada@example.com', password: ' secret1 '),
    ]);
  });

  testWidgets('an email with a space inside is refused', (tester) async {
    await pumpLogin(tester);

    await submit(
      tester,
      email: 'ada lovelace@example.com',
      password: 'secret1',
    );

    expect(find.text(l10nOf(tester).invalidEmail), findsOneWidget);
    expect(repository.logins, isEmpty);
  });

  testWidgets('while signing in the spinner has a spoken label, and the '
      'button swallows a second tap', (tester) async {
    final semantics = tester.ensureSemantics();
    final slow = Completer<Result<UserEntity>>();
    repository.pendingLogin = slow.future;
    await pumpLogin(tester);

    // `submit` settles the frame; a spinner never does.
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.first, 'ada@example.com');
    await tester.enterText(fields.last, 'secret1');
    final signIn = find.text(l10nOf(tester).signIn).last;
    await tester.ensureVisible(signIn);
    await tester.tap(signIn);
    await tester.pump();
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.bySemanticsLabel('Loading'), findsOneWidget);

    final button = find.byType(MaterialButton);
    await tester.tap(button);
    await tester.pump();
    expect(repository.logins, hasLength(1));

    slow.complete(const Result.success(UserEntity(id: '1', name: 'Ada')));
    await tester.pumpAndSettle();
    semantics.dispose();
  });

  testWidgets('the password field is obscured until its toggle is tapped', (
    tester,
  ) async {
    await pumpLogin(tester);
    final password = find.descendant(
      of: find.byType(TextFormField).last,
      matching: find.byType(EditableText),
    );
    expect(tester.widget<EditableText>(password).obscureText, isTrue);

    await tester.tap(find.byTooltip(l10nOf(tester).showPassword));
    await tester.pump();

    expect(tester.widget<EditableText>(password).obscureText, isFalse);
  });
}
