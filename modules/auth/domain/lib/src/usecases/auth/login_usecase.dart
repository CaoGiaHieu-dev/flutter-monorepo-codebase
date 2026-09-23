import 'package:domain_core/domain_core.dart';
import 'package:injectable/injectable.dart';

import '../../entities/user/user.dart';
import '../../params/auth_params/login_params.dart';
import '../../repositories/i_auth_repository.dart';

/// Authenticates a user with email and password.
@injectable
class LoginUseCase extends BaseUseCase<UserEntity, LoginParams> {
  LoginUseCase(this._authRepository);

  final IAuthRepository _authRepository;

  @override
  Future<Result<UserEntity>> call(LoginParams params) {
    return _authRepository.login(params);
  }
}
