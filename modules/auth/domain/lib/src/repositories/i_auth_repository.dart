import 'package:domain_core/domain_core.dart';

import '../entities/user_entity.dart';
import '../params/login_params.dart';

/// SAMPLE — the repository contract for the auth module.
///
/// Every method returns [Result] rather than throwing. That is the boundary
/// rule: the data layer converts exceptions to an `AppFailure`, so nothing
/// above this line needs a `try`.
abstract class IAuthRepository {
  /// Authenticates a user and persists the resulting session.
  Future<Result<UserEntity>> login(LoginParams params);

  /// Drops the stored session.
  Future<Result<void>> logout();

  /// Exchanges the stored credentials for a fresh token.
  ///
  /// The transport's session gateway calls this when a request comes back
  /// `401`; a failure that never reached the server stays a failure, so the
  /// gateway can tell "offline" from "refused".
  Future<Result<UserEntity>> refreshToken();

  /// Brings back the stored session at app start.
  ///
  /// Renews it like [refreshToken]; when the renewal never got the server's
  /// verdict (no network, a 5xx) the user stored at the last sign-in is
  /// returned instead, so an offline start keeps the user signed in. A
  /// refusal ends the session.
  Future<Result<UserEntity>> restoreSession();
}
