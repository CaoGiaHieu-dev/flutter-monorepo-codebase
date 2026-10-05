import 'package:domain_auth/domain_auth.dart';
import 'package:domain_core/domain_core.dart';
import 'package:test/test.dart';

/// A hand-written [IAuthRepository] (RULE-61): the use case hands its input to
/// the repository untouched and returns the [Result] without wrapping it.
class _FakeAuthRepository implements IAuthRepository {
  Result<UserEntity> loginResult = const Result.success(_ada);
  final logins = <LoginParams>[];

  @override
  Future<Result<UserEntity>> login(LoginParams params) async {
    logins.add(params);
    return loginResult;
  }

  @override
  Future<Result<void>> logout() => throw UnimplementedError();

  @override
  Future<Result<UserEntity>> refreshToken() => throw UnimplementedError();
}

const _ada = UserEntity(id: '1', email: 'ada@example.com', name: 'Ada');
const _params = LoginParams(email: 'ada@example.com', password: 'secret');

void main() {
  test('LoginUseCase forwards the params and returns the entity', () async {
    final repository = _FakeAuthRepository();

    final result = await LoginUseCase(repository)(_params);

    expect(repository.logins, [_params]);
    expect(result.dataOrNull, _ada);
  });

  test('LoginUseCase returns a failure as a failure, never throws', () async {
    final repository = _FakeAuthRepository()
      ..loginResult = const Result.failure(
        AuthFailure(message: 'Unauthorized', code: 401),
      );

    final result = await LoginUseCase(repository)(_params);

    expect(result.errorOrNull, isA<AuthFailure<dynamic>>());
  });
}
