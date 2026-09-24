import 'package:core_di/core_di.dart';
import 'package:domain_auth/domain_auth.dart';
import 'package:domain_core/domain_core.dart';
import 'package:feature_auth/feature_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider_state_management/provider_state_management.dart';

/// A hand-written [IAuthRepository]. The real use cases wrap it, so the
/// provider is exercised through exactly the calls it makes in the app.
class _FakeAuthRepository implements IAuthRepository {
  Result<UserEntity> refreshResult = const Result.failure(
    AuthFailure(message: 'no session', code: 401),
  );
  Result<UserEntity> loginResult = const Result.success(_ada);

  final logins = <LoginParams>[];
  int logouts = 0;

  @override
  Future<Result<UserEntity>> login(LoginParams params) async {
    logins.add(params);
    return loginResult;
  }

  @override
  Result<void> logout() {
    logouts++;
    return const Result.success();
  }

  @override
  Future<Result<UserEntity>> refreshToken() async => refreshResult;
}

const _ada = UserEntity(id: '1', email: 'ada@example.com', name: 'Ada');

void main() {
  late _FakeAuthRepository repository;
  late AuthStatusStreamImpl statusStream;

  setUp(() {
    repository = _FakeAuthRepository();
    statusStream = AuthStatusStreamImpl();
  });

  /// Builds the provider and waits for its session restore to finish.
  Future<AuthProvider> buildProvider() async {
    final provider = AuthProvider(
      LoginUseCase(repository),
      LogoutUseCase(repository),
      RefreshTokenUseCase(repository),
      statusStream,
    );
    addTearDown(provider.dispose);
    await provider.ensureInitialized();
    return provider;
  }

  group('session restore', () {
    test('a stored session signs the user straight back in', () async {
      repository.refreshResult = const Result.success(_ada);

      final provider = await buildProvider();

      expect(provider.hasRestoredSession, isTrue);
      expect(provider.data, _ada);
      expect(provider.signedInUser?.id, '1');
      expect(provider.signedInUser?.email, 'ada@example.com');
      expect(statusStream.currentUser?.displayName, 'Ada');
    });

    test('no session leaves the user signed out, not in error', () async {
      final provider = await buildProvider();

      expect(provider.hasRestoredSession, isTrue);
      expect(provider.isSuccess, isTrue);
      expect(provider.data, isNull);
      expect(provider.signedInUser, isNull);
    });
  });

  group('login', () {
    test('success stores the user and publishes the principal', () async {
      final provider = await buildProvider();
      final published = <SessionPrincipal?>[];
      final sub = provider.sessionChanges.listen(published.add);
      addTearDown(sub.cancel);

      await provider.login('ada@example.com', 'hunter2');
      await pumpEventQueue();

      expect(repository.logins, const [
        LoginParams(email: 'ada@example.com', password: 'hunter2'),
      ]);
      expect(provider.isSuccess, isTrue);
      expect(provider.data, _ada);
      expect(published.map((p) => p?.id), contains('1'));
      expect(statusStream.currentUser?.id, '1');
    });

    test('a 401 becomes invalid credentials, on both channels', () async {
      repository.loginResult = const Result.failure(
        AuthFailure(message: 'Unauthorized', code: 401),
      );
      final provider = await buildProvider();
      final failures = <SessionFailure>[];
      final sub = provider.sessionFailures.listen(failures.add);
      addTearDown(sub.cancel);

      await provider.login('ada@example.com', 'wrong');
      await pumpEventQueue();

      expect(provider.isError, isTrue);
      expect(
        provider.viewState.state,
        const ViewState.error(error: AuthErrorState.invalidCredentials()),
      );
      expect(provider.viewState.message, 'Unauthorized');
      expect(failures.single, isA<SessionInvalidCredentialsFailure>());
      expect(provider.signedInUser, isNull);
    });

    test('a 404 is published as user-not-found', () async {
      repository.loginResult = const Result.failure(
        ServerFailure(message: 'Not found', code: 404),
      );
      final provider = await buildProvider();
      final failures = <SessionFailure>[];
      final sub = provider.sessionFailures.listen(failures.add);
      addTearDown(sub.cancel);

      await provider.login('nobody@example.com', 'x');
      await pumpEventQueue();

      expect(failures.single, isA<SessionUserNotFoundFailure>());
    });

    test('any other failure keeps the backend message', () async {
      repository.loginResult = const Result.failure(
        ServerFailure(message: 'Maintenance', code: 503),
      );
      final provider = await buildProvider();
      final failures = <SessionFailure>[];
      final sub = provider.sessionFailures.listen(failures.add);
      addTearDown(sub.cancel);

      await provider.login('ada@example.com', 'x');
      await pumpEventQueue();

      final failure = failures.single;
      expect(failure, isA<SessionServerFailure>());
      failure as SessionServerFailure;
      expect(failure.message, 'Maintenance');
      expect(failure.code, 503);
    });
  });

  test('logout clears the local session and signs the user out', () async {
    repository.refreshResult = const Result.success(_ada);
    final provider = await buildProvider();
    expect(provider.signedInUser, isNotNull);

    await provider.logout();
    await pumpEventQueue();

    expect(repository.logouts, 1);
    expect(provider.data, isNull);
    expect(provider.signedInUser, isNull);
    expect(statusStream.currentUser, isNull);
  });

  test('a session lost in the transport signs the user out', () async {
    repository.refreshResult = const Result.success(_ada);
    final provider = await buildProvider();

    provider.onSessionLost();
    await pumpEventQueue();

    expect(provider.signedInUser, isNull);
    expect(repository.logouts, 0, reason: 'storage is already cleared');
  });
}
