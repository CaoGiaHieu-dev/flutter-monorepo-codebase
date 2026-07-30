import 'package:domain_core/domain_core.dart';
import 'package:injectable/injectable.dart';

import '../../entities/user/user.dart';
import '../../repositories/i_auth_repository.dart';

@injectable
class RefreshTokenUseCase extends BaseUseCase<UserEntity, NoParams> {
  RefreshTokenUseCase(this._authRepository);

  final IAuthRepository _authRepository;

  @override
  Future<Result<UserEntity>> call(NoParams params) {
    // Repository now returns Result<UserEntity> directly - no unwrapping needed
    return _authRepository.refreshToken();
  }
}
