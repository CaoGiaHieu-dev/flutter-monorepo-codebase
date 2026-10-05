import 'dart:async';

import 'package:domain_auth/domain_auth.dart';
import 'package:domain_core/domain_core.dart';

const ada = UserEntity(id: '1', email: 'ada@example.com', name: 'Ada');

/// A hand-written [IAuthRepository] (RULE-61). The real use case wraps it, so
/// the provider is exercised through exactly the calls it makes in the app.
class FakeAuthRepository implements IAuthRepository {
  /// What the start-up session restore (`refreshToken`) answers.
  Result<UserEntity> refreshResult = const Result.failure(
    AuthFailure(message: 'no session', code: 401),
  );
  Result<UserEntity> loginResult = const Result.success(ada);

  /// When set, `login` waits for it instead of answering at once.
  Future<Result<UserEntity>>? pendingLogin;

  final logins = <LoginParams>[];
  int logouts = 0;

  @override
  Future<Result<UserEntity>> login(LoginParams params) async {
    logins.add(params);
    return pendingLogin ?? loginResult;
  }

  @override
  Future<Result<void>> logout() async {
    logouts++;
    return const Result.success();
  }

  @override
  Future<Result<UserEntity>> refreshToken() async => refreshResult;
}
