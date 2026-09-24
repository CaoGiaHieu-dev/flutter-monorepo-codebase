import 'package:core_di/core_di.dart';
import 'package:domain_auth/domain_auth.dart';
import 'package:injectable/injectable.dart';
import 'package:platform_kernel/platform_kernel.dart';

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
  /// the session: no network ([NetworkFailure]), a real HTTP 5xx, or a
  /// cancelled request. Every other failure means the server answered and
  /// refused — a 401/403, another 4xx, or a 200 whose envelope reports an
  /// error (`ErrorCodes.RESPONSE_REJECTED`) — and returns null.
  ///
  /// The envelope case used to arrive as `ServerFailure(code: 500)`, which
  /// this read as "server down": the dead session was kept, and every later
  /// 401 retried the same refused renewal forever.
  @override
  Future<String?> refreshToken() async {
    final result = await _repository.refreshToken();
    if (result.isSuccess) return _local.getUserToken();
    final failure = result.errorOrNull;
    if (isTransient(failure)) {
      throw StateError(
        'Session renewal did not reach the server: '
        '${failure?.message}',
      );
    }
    return null;
  }

  /// Whether [failure] says nothing about the session's validity — the
  /// renewal never got an answer — so the session must be kept.
  ///
  /// Exposed for tests: this predicate decides whether a user is signed out.
  static bool isTransient(AppFailure<dynamic>? failure) {
    if (failure is NetworkFailure) return true;
    if (failure is! ServerFailure) return false;
    final code = failure.code;
    if (code == null) return false;
    return (code >= 500 && code < 600) || code == ErrorCodes.REQUEST_CANCELLED;
  }

  @override
  Future<void> clearSession() async => _local.clearAllAuthData();
}
