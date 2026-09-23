import 'package:domain_core/domain_core.dart';

import '../entities/user/user.dart';
import '../params/auth_params/login_params.dart';

/// SAMPLE — the repository contract for the auth module.
///
/// Every method returns [Result] rather than throwing. That is the boundary
/// rule: the data layer converts exceptions to an `AppFailure`, so nothing
/// above this line needs a `try`.
abstract class IAuthRepository {
  /// Authenticates a user and persists the resulting session.
  Future<Result<UserEntity>> login(LoginParams params);

  /// Drops the local session. Synchronous — it only clears storage.
  Result<void> logout();

  /// Exchanges the stored credentials for a fresh token.
  Future<Result<UserEntity>> refreshToken();
}
