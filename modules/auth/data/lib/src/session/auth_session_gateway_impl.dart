import 'package:core_di/core_di.dart';
import 'package:domain_auth/domain_auth.dart';
import 'package:injectable/injectable.dart';
import 'package:platform_kernel/platform_kernel.dart';

import '../data_sources/local/auth_local_data_source.dart';

/// SAMPLE — hands the transport layer a session without it knowing this module
/// exists: the shell resolves `ISessionGateway` with `getItOrNull`, so an app
/// composed without auth still builds. A lazy singleton, like the data source
/// it reads.
@LazySingleton(as: ISessionGateway)
class AuthSessionGatewayImpl implements ISessionGateway {
  AuthSessionGatewayImpl(this._local, this._repository);

  final AuthLocalDataSource _local;
  final IAuthRepository _repository;

  @override
  String? readToken() => _local.getUserToken();

  /// The repository stores the new token; this re-reads it. Only a failure
  /// that never got the server's verdict throws (the session is kept); every
  /// refusal returns null (the transport ends the session).
  @override
  Future<String?> refreshToken() async {
    final result = await _repository.refreshToken();
    if (result.isSuccess) return _local.getUserToken();
    final failure = result.errorOrNull;
    if (_isTransient(failure)) {
      throw StateError('Session renewal got no answer: ${failure?.message}');
    }
    return null;
  }

  @override
  Future<void> clearSession() => _local.clearUserToken();

  /// No network, a bad certificate, a cancelled request or a real HTTP 5xx say
  /// nothing about the session. Anything else means the server answered and
  /// refused: a 4xx, or a 200 whose envelope reports an error.
  static bool _isTransient(AppFailure<dynamic>? failure) {
    if (failure is NetworkFailure) return true;
    final code = failure is ServerFailure ? failure.code : null;
    return code != null &&
        ((code >= 500 && code < 600) ||
            code == ErrorCodes.REQUEST_CANCELLED ||
            code == ErrorCodes.BAD_CERTIFICATE);
  }
}
