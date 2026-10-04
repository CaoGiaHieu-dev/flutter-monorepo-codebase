import 'package:auth_api/auth_api.dart';
import 'package:core_di/core_di.dart';
import 'package:domain_auth/domain_auth.dart';
import 'package:domain_core/domain_core.dart';
import 'package:feature_auth/feature_auth.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _FakeAuthRepository implements IAuthRepository {
  int logouts = 0;

  @override
  Future<Result<UserEntity>> login(LoginParams params) async =>
      const Result.failure(AuthFailure(message: 'nope', code: 401));

  @override
  Future<Result<void>> logout() async {
    logouts++;
    return const Result.success();
  }

  @override
  Future<Result<UserEntity>> refreshToken() => restoreSession();

  @override
  Future<Result<UserEntity>> restoreSession() async =>
      const Result.failure(AuthFailure(message: 'no session', code: 401));
}

void main() {
  late _FakeAuthRepository repository;
  late AuthProvider auth;

  setUp(() {
    repository = _FakeAuthRepository();
    auth = AuthProvider(
      LoginUseCase(repository),
      LogoutUseCase(repository),
      RestoreSessionUseCase(repository),
      AuthStatusStreamImpl(),
    );
  });

  tearDown(() => auth.dispose());

  group('AuthStatusStreamImpl.toPrincipal', () {
    test('no user is no principal', () {
      expect(AuthStatusStreamImpl.toPrincipal(null), isNull);
    });

    test('maps identity fields and the role to a plain-string tag', () {
      final principal = AuthStatusStreamImpl.toPrincipal(
        const UserEntity(
          id: '1',
          email: 'ada@example.com',
          name: 'Ada',
          role: UserRole.owner,
        ),
      );

      expect(
        principal,
        const SessionPrincipal(
          id: '1',
          displayName: 'Ada',
          email: 'ada@example.com',
          roles: {'owner'},
        ),
      );
    });

    test('a user without a role carries no role tags', () {
      final principal = AuthStatusStreamImpl.toPrincipal(
        const UserEntity(id: '1'),
      );

      expect(principal?.roles, isEmpty);
    });
  });

  test('updateAuthStatus updates currentUser and notifies listeners', () async {
    final stream = AuthStatusStreamImpl();
    addTearDown(stream.dispose);
    final seen = <SessionPrincipal?>[];
    stream.sessionStatusStream.listen(seen.add);

    stream.updateAuthStatus(const UserEntity(id: '1', name: 'Ada'));
    stream.updateAuthStatus(null);
    await pumpEventQueue();

    expect(seen.map((p) => p?.id), ['1', null]);
    expect(stream.currentUser, isNull);
  });

  testWidgets('AuthTreeWrapper puts the app-wide AuthProvider above the app', (
    tester,
  ) async {
    late AuthProvider found;
    await tester.pumpWidget(
      Builder(
        builder: (context) => AuthTreeWrapper(auth).wrap(
          context,
          Builder(
            builder: (inner) {
              found = inner.read<AuthProvider>();
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    expect(found, same(auth));
  });

  testWidgets(
    'AuthActionHandlerImpl.logout ends the session through the provider',
    (
      tester,
    ) async {
      late BuildContext context;
      await tester.pumpWidget(
        ChangeNotifierProvider<AuthProvider>.value(
          value: auth,
          child: Builder(
            builder: (c) {
              context = c;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      final IAuthActionHandler handler = AuthActionHandlerImpl();
      await handler.logout(context);

      expect(repository.logouts, 1);
    },
  );

  test('the shell is sent to the login route when signed out', () {
    expect(AuthSignInLocation().path, AuthPath.LOGIN);
    expect(const LoginRoute().location, AuthPath.LOGIN);
  });
}
