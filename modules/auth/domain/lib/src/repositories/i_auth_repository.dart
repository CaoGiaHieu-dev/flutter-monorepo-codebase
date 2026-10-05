import 'package:domain_core/domain_core.dart';

import '../entities/user_entity.dart';
import '../params/login_params.dart';

/// SAMPLE — the repository contract. Every method returns [Result]: the data
/// layer turns exceptions into an `AppFailure`, so nothing above needs a `try`.
abstract class IAuthRepository {
  /// Authenticates a user and stores the resulting session.
  Future<Result<UserEntity>> login(LoginParams params);

  /// Drops the stored session.
  Future<Result<void>> logout();

  /// Renews the stored session — at app start and after a `401`. With nothing
  /// stored it fails at once, without a network call.
  Future<Result<UserEntity>> refreshToken();
}
