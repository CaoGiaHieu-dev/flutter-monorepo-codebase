import 'package:core_di/core_di.dart';
import 'package:domain_auth/domain_auth.dart';
import 'package:domain_core/domain_core.dart';
import 'package:injectable/injectable.dart';

import '../data_sources/local/auth_local_data_source.dart';

/// SAMPLE — how the auth module hands the transport layer a session without
/// the transport layer knowing this module exists.
///
/// The shell's `NetworkConfigImpl` resolves this contract with `getItOrNull`
/// instead of importing anything from here, so it still compiles and runs in
/// an app that composes no auth module.
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
  ///
  /// A failure that never got an answer from the server — no network, a 5xx,
  /// a cancelled request — throws, which keeps the session; any other failure
  /// means the server refused, and returns null.
  @override
  Future<String?> refreshToken() async {
    final result = await _repository.refreshToken();
    if (result.isSuccess) return _local.getUserToken();
    final failure = result.errorOrNull;
    final transient =
        failure is NetworkFailure ||
        (failure is ServerFailure && (failure.code ?? 500) >= 500);
    if (transient) {
      throw StateError(
        'Session renewal did not reach the server: '
        '${failure?.message}',
      );
    }
    return null;
  }

  @override
  Future<void> clearSession() async => _local.clearAllAuthData();
}
