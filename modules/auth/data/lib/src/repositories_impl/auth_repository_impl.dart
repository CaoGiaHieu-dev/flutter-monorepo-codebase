import 'package:data_core/data_core.dart';
import 'package:domain_auth/domain_auth.dart';
import 'package:domain_core/domain_core.dart';
import 'package:injectable/injectable.dart';

import '../data_sources/local/auth_local_data_source.dart';
import '../data_sources/remote/auth_remote_data_source.dart';
import '../models/user_model.dart';
import '../session/transient_failure.dart';

/// SAMPLE — the auth repository, written the way this template documents.
///
/// It talks to a Retrofit data source for the network and a `StorageValue`
/// data source for the session, wraps both in `execute()` so nothing throws
/// past this layer, and converts `UserModel` to `UserEntity` at the boundary.
/// Nothing above this file ever sees a model.
///
/// Swap the transport (Firebase, GraphQL) if your product needs to; keep the
/// shape. If you do move to Firebase, register an `ErrorClassifier` for its
/// exceptions first (`ErrorHandler.registerClassifier`, RULE-43) — without
/// one every Firebase error arrives as `ServerFailure(ErrorCodes.UNKNOWN)`.
@LazySingleton(as: IAuthRepository)
class AuthRepositoryImpl extends BaseRepository implements IAuthRepository {
  AuthRepositoryImpl(this._remote, this._local);

  final AuthRemoteDataSource _remote;
  final AuthLocalDataSource _local;

  @override
  Future<Result<UserEntity>> login(LoginParams params) {
    return _authenticate(
      () => _remote.login({'email': params.email, 'password': params.password}),
    );
  }

  /// With no stored token there is no session to renew: answer without a
  /// network call — which at boot would otherwise hit the API on every fresh
  /// install. A refusal from the server (401/403) ends the stored session
  /// too, so an expired token is not attached to every later request.
  @override
  Future<Result<UserEntity>> refreshToken() async {
    if (_local.getUserToken() == null) {
      return const Result.failure(
        AppFailure.auth(message: 'No stored session', code: 401),
      );
    }
    final result = await _authenticate(_remote.refreshToken);
    if (result.errorOrNull is AuthFailure) await _local.clearAllAuthData();
    return result;
  }

  /// A renewal that never reached the server says nothing about the session,
  /// so the user stored at the last sign-in stands in for the answer: an
  /// app started offline opens signed in, and the next request that gets
  /// through renews the token (or ends the session) as usual.
  @override
  Future<Result<UserEntity>> restoreSession() async {
    final result = await refreshToken();
    if (!isTransientFailure(result.errorOrNull)) return result;
    final stored = _local.getUserData();
    return stored == null ? result : Result.success(stored.toEntity());
  }

  @override
  Future<Result<void>> logout() {
    return execute<void, void>(_local.clearAllAuthData);
  }

  /// The one shape both endpoints share: call, verify the envelope, persist
  /// the session, hand back an entity.
  ///
  /// `successCondition` is what turns a 200-with-error-body into a `Failure`.
  /// Without it `execute` treats any response that did not throw as a success,
  /// and an API that reports failure in the payload would log the user in.
  Future<Result<UserEntity>> _authenticate(
    Future<BaseEntity<UserModel>> Function() request,
  ) {
    return execute<BaseEntity<UserModel>, UserEntity>(
      request,
      successCondition: (response) =>
          response.isSuccess && response.data != null,
      onSuccess: (response) async {
        final user = response.data!;
        await _local.saveUserToken(user.token);
        await _local.saveUserData(user);
      },
      mapper: (response) => response.data!.toEntity(),
    );
  }
}
