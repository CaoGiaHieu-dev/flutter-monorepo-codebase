import 'package:domain_core/domain_core.dart';
import 'package:injectable/injectable.dart';

import '../../entities/user/user.dart';
import '../../params/auth_params/login_params.dart';
import '../../repositories/i_auth_repository.dart';

/// Login use case - authenticates user with credentials
///
/// This use case trusts that LoginParams are already validated at construction.
/// If params are invalid, they would have thrown ArgumentError during creation.
@injectable
class LoginUseCase extends BaseUseCase<UserEntity, LoginParams> {
  LoginUseCase(this._authRepository);

  final IAuthRepository _authRepository;

  @override
  Future<Result<UserEntity>> call(LoginParams params) {
    // Params are already validated at construction - no need to validate here
    // Repository returns Result<UserEntity> directly - no unwrapping needed
    return _authRepository.login(params);
  }
}
