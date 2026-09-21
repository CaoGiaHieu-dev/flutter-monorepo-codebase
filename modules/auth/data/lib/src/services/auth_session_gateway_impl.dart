import 'package:core_di/core_di.dart';
import 'package:domain_auth/domain_auth.dart';
import 'package:injectable/injectable.dart';

import '../data_sources/local/auth_local_data_source.dart';

/// SAMPLE — how the auth module hands the transport layer a session without
/// the transport layer knowing this module exists.
///
/// The app shell's `NetworkConfigImpl` used to import `AuthLocalDataSource`
/// and `RefreshTokenUseCase` from here directly, which meant the shell could
/// not compile without the auth module — the template promised removable
/// modules and then broke that promise in its own composition root.
///
/// Registered as a singleton because [AuthLocalDataSource] is: a factory would
/// hand each caller a gateway over a different, empty cache.
@LazySingleton(as: IAuthSessionGateway)
class AuthSessionGatewayImpl implements IAuthSessionGateway {
  AuthSessionGatewayImpl(this._local, this._repository);

  final AuthLocalDataSource _local;
  final IAuthRepository _repository;

  @override
  String? readToken() => _local.getUserToken();

  /// The repository persists the new credentials, so this only re-reads the
  /// value from its owner rather than storing anything itself.
  @override
  Future<String?> refreshToken() async {
    final result = await _repository.refreshToken();
    if (!result.isSuccess) return null;
    return _local.getUserToken();
  }

  @override
  Future<void> clearSession() async => _local.clearAllAuthData();
}
