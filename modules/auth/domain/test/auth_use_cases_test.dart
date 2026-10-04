import 'package:domain_auth/domain_auth.dart';
import 'package:domain_core/domain_core.dart';
import 'package:test/test.dart';

/// A hand-written [IAuthRepository]. Each use case is a one-line delegation,
/// so what matters is that it forwards its input untouched and hands back the
/// repository's [Result] — success or failure — without wrapping or throwing.
class _FakeAuthRepository implements IAuthRepository {
  Result<UserEntity> loginResult = const Result.success(_ada);
  Result<void> logoutResult = const Result.success();
  Result<UserEntity> restoreResult = const Result.success(_ada);

  final logins = <LoginParams>[];
  int logouts = 0;
  int restores = 0;

  @override
  Future<Result<UserEntity>> login(LoginParams params) async {
    logins.add(params);
    return loginResult;
  }

  @override
  Future<Result<void>> logout() async {
    logouts++;
    return logoutResult;
  }

  @override
  Future<Result<UserEntity>> refreshToken() async =>
      throw UnimplementedError('no use case refreshes a token');

  @override
  Future<Result<UserEntity>> restoreSession() async {
    restores++;
    return restoreResult;
  }
}

const _ada = UserEntity(
  id: '1',
  email: 'ada@example.com',
  name: 'Ada',
  role: UserRole.owner,
);

const _rejected = AuthFailure<dynamic>(message: 'bad credentials', code: 401);

void main() {
  late _FakeAuthRepository repository;

  setUp(() => repository = _FakeAuthRepository());

  group('LoginUseCase', () {
    test('forwards the params and returns the signed-in user', () async {
      const params = LoginParams(email: 'ada@example.com', password: 'pw');

      final result = await LoginUseCase(repository)(params);

      expect(result.dataOrNull, _ada);
      expect(repository.logins, [params]);
    });

    test('returns the repository failure as it is, without throwing', () async {
      repository.loginResult = const Result.failure(_rejected);

      final result = await LoginUseCase(repository)(
        const LoginParams(email: 'ada@example.com', password: 'wrong'),
      );

      expect(result.isFailure, isTrue);
      expect(result.errorOrNull, _rejected);
      expect(result.dataOrNull, isNull);
    });
  });

  group('LogoutUseCase', () {
    test('asks the repository to drop the session once', () async {
      final result = await LogoutUseCase(repository)(const NoParams());

      expect(result.isSuccess, isTrue);
      expect(repository.logouts, 1);
    });

    test('returns a failed logout as a failure', () async {
      const failure = StorageFailure<dynamic>(message: 'keystore locked');
      repository.logoutResult = const Result.failure(failure);

      final result = await LogoutUseCase(repository)(const NoParams());

      expect(result.errorOrNull, failure);
    });
  });

  group('RestoreSessionUseCase', () {
    test('returns the restored user', () async {
      final result = await RestoreSessionUseCase(repository)(const NoParams());

      expect(result.dataOrNull, _ada);
      expect(repository.restores, 1);
    });

    test('a refused session is a failure, not an empty success', () async {
      repository.restoreResult = const Result.failure(_rejected);

      final result = await RestoreSessionUseCase(repository)(const NoParams());

      expect(result.isFailure, isTrue);
      expect(result.errorOrNull, _rejected);
    });
  });
}
