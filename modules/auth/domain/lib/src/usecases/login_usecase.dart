import 'package:domain_core/domain_core.dart';
import 'package:injectable/injectable.dart';

import '../entities/user_entity.dart';
import '../params/login_params.dart';
import '../repositories/i_auth_repository.dart';

/// Authenticates a user with email and password.
@injectable
class LoginUseCase extends BaseUseCase<UserEntity, LoginParams> {
  LoginUseCase(this._repository);

  final IAuthRepository _repository;

  @override
  Future<Result<UserEntity>> call(LoginParams params) =>
      _repository.login(params);
}
