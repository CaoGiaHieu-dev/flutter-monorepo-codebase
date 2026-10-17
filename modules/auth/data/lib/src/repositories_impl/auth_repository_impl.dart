import 'package:data_core/data_core.dart';
import 'package:domain_auth/domain_auth.dart';
import 'package:domain_core/domain_core.dart';
import 'package:injectable/injectable.dart';

import '../data_sources/local/auth_local_data_source.dart';
import '../data_sources/remote/auth_remote_data_source.dart';
import '../models/user_model.dart';

/// SAMPLE — a Retrofit data source for the network and a `StorageValue` data
/// source for the token, both wrapped in `execute()` so nothing throws past
/// this layer, with `UserModel` converted to `UserEntity` at the boundary.
///
/// Swapping the transport (Firebase, GraphQL) keeps this shape; register an
/// `ErrorClassifier` for its exceptions first (RULE-43).
@LazySingleton(as: IAuthRepository)
class AuthRepositoryImpl extends BaseRepository implements IAuthRepository {
  AuthRepositoryImpl(this._remote, this._local);

  final AuthRemoteDataSource _remote;
  final AuthLocalDataSource _local;

  @override
  Future<Result<UserEntity>> login(LoginParams params) => _authenticate(
    () => _remote.login({'email': params.email, 'password': params.password}),
    requiresToken: true,
  );

  /// With no stored token there is no session to renew: answer without a
  /// network call, which at boot would otherwise hit the API on every fresh
  /// install. A refusal (401/403) drops the dead token.
  @override
  Future<Result<UserEntity>> refreshToken() async {
    if (_local.getUserToken() == null) {
      return const Result.failure(
        AppFailure.auth(message: 'No stored session', code: 401),
      );
    }
    final result = await _authenticate(_remote.refreshToken);
    if (result.errorOrNull is AuthFailure) await _local.clearUserToken();
    return result;
  }

  @override
  Future<Result<void>> logout() => execute<void, void>(_local.clearUserToken);

  /// Call, verify the envelope, store the token, hand back an entity.
  ///
  /// `successCondition` is what turns a 200-with-error-body into a failure:
  /// without it `execute` treats any response that did not throw as success.
  /// A sign-in answer without a token is no session ([requiresToken]); a
  /// renewal that omits it (a backend that does not rotate) keeps the stored one.
  Future<Result<UserEntity>> _authenticate(
    Future<BaseEntity<UserModel>> Function() request, {
    bool requiresToken = false,
  }) {
    return execute<BaseEntity<UserModel>, UserEntity>(
      request,
      successCondition: (response) {
        final user = response.data;
        return response.isSuccess &&
            user != null &&
            (!requiresToken || _hasToken(user));
      },
      onSuccess: (response) async {
        final user = response.data!;
        if (_hasToken(user)) await _local.saveUserToken(user.token!);
      },
      mapper: (response) => response.data!.toEntity(),
    );
  }

  static bool _hasToken(UserModel user) => user.token?.isNotEmpty ?? false;
}
