import 'package:domain_core/domain_core.dart';
import 'package:injectable/injectable.dart';

import '../../repositories/i_auth_repository.dart';

@injectable
class LogoutUseCase extends BaseUseCase<void, NoParams> {
  LogoutUseCase(this._authRepository);

  final IAuthRepository _authRepository;

  @override
  Result<void> call(NoParams params) {
    // Repository now returns Result<void> directly, so the use case is also synchronous.
    return _authRepository.logout();
  }
}
