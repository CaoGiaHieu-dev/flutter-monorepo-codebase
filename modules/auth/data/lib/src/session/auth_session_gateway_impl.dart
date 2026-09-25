import 'package:core_di/core_di.dart';
import 'package:domain_auth/domain_auth.dart';
import 'package:injectable/injectable.dart';

import '../data_sources/local/auth_local_data_source.dart';
import 'transient_failure.dart';

/// SAMPLE — how the auth module hands the transport layer a session without
/// the transport layer knowing this module exists.
///
/// The shell's `NetworkConfigImpl` resolves this contract with `getItOrNull`
/// instead of importing anything from here, so it still compiles and runs in
/// an app that composes no auth module.
///
/// Registered as a singleton because [AuthLocalDataSource] is: a factory would
/// hand each caller a gateway over a different, empty cache.
@LazySingleton(as: ISessionGateway)
class AuthSessionGatewayImpl implements ISessionGateway {
  AuthSessionGatewayImpl(this._local, this._repository);

  final AuthLocalDataSource _local;
  final IAuthRepository _repository;

  @override
  String? readToken() => _local.getUserToken();

  /// The repository persists the new credentials, so this only re-reads the
  /// value from its owner rather than storing anything itself.
  ///
  /// Only a failure that never got the server's verdict throws, which keeps
  /// the session ([isTransientFailure]); every refusal returns null.
  ///
  /// The envelope case used to arrive as `ServerFailure(code: 500)`, which
  /// this read as "server down": the dead session was kept, and every later
  /// 401 retried the same refused renewal forever.
  @override
  Future<String?> refreshToken() async {
    final result = await _repository.refreshToken();
    if (result.isSuccess) return _local.getUserToken();
    final failure = result.errorOrNull;
    if (isTransientFailure(failure)) {
      throw StateError(
        'Session renewal did not reach the server: '
        '${failure?.message}',
      );
    }
    return null;
  }

  @override
  Future<void> clearSession() => _local.clearAllAuthData();
}
