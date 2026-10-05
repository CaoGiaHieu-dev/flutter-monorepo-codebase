import 'package:core_network/core_network.dart';
import 'package:dio/dio.dart';
import 'package:domain_core/domain_core.dart';
import 'package:retrofit/retrofit.dart';

import '../../models/user_model.dart';
import '../../utils/auth_constants.dart';

part 'auth_remote_data_source.g.dart';

/// Type-safe HTTP calls through Retrofit. Returns the `BaseEntity<T>` envelope;
/// the repository turns it into a `Result<T>`.
@RestApi()
abstract class AuthRemoteDataSource {
  factory AuthRemoteDataSource(Dio dio, {String? baseUrl}) =
      _AuthRemoteDataSource;

  /// A `401` here means wrong credentials, not an expired session, so it must
  /// not start a token refresh.
  @POST(AuthApiConstants.LOGIN)
  @Extra({NetworkConstants.EXTRA_CAN_REFRESH_TOKEN: false})
  Future<BaseEntity<UserModel>> login(@Body() Map<String, dynamic> loginData);

  /// Runs inside a refresh or at boot, so it neither refreshes on a `401`
  /// (it would wait on itself) nor raises the retry dialog (it would block
  /// boot on the user's answer): it fails fast and the caller decides.
  @POST(AuthApiConstants.REFRESH_TOKEN)
  @Extra({
    NetworkConstants.EXTRA_CAN_REFRESH_TOKEN: false,
    NetworkConstants.EXTRA_CAN_RETRY: false,
  })
  Future<BaseEntity<UserModel>> refreshToken();
}
