import 'package:domain_core/domain_core.dart';
import 'package:injectable/injectable.dart';

import '../entities/user_entity.dart';
import '../repositories/i_auth_repository.dart';

/// Restores the stored session at app start — see
/// [IAuthRepository.restoreSession] for how an offline start is handled.
@injectable
class RestoreSessionUseCase extends BaseUseCase<UserEntity, NoParams> {
  RestoreSessionUseCase(this._authRepository);

  final IAuthRepository _authRepository;

  @override
  Future<Result<UserEntity>> call(NoParams params) {
    return _authRepository.restoreSession();
  }
}
