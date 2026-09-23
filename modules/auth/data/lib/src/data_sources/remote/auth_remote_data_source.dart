import 'package:core_network/core_network.dart';
import 'package:dio/dio.dart';
import 'package:domain_core/domain_core.dart';
import 'package:retrofit/retrofit.dart';

import '../../models/user/user_model.dart';
import '../../utils/auth_api_constants.dart';

part 'auth_remote_data_source.g.dart';

/// Remote data source for authentication API calls
///
/// This data source uses Retrofit for type-safe HTTP API calls.
/// It returns BaseEntity<T> which wraps API responses with status codes
/// and messages. The repository layer converts these to Result<T>.
@RestApi()
abstract class AuthRemoteDataSource {
  factory AuthRemoteDataSource(Dio dio, {String? baseUrl}) =
      _AuthRemoteDataSource;

  /// Authenticates user with provided credentials.
  ///
  /// A `401` here means wrong credentials, not an expired session — so it
  /// must not start a token refresh.
  @POST(AuthApiConstants.LOGIN)
  @Extra({NetworkConstants.EXTRA_CAN_REFRESH_TOKEN: false})
  Future<BaseEntity<UserModel>> login(@Body() Map<String, dynamic> loginData);

  /// Refreshes the current authentication token.
  ///
  /// Runs *inside* a refresh, or at boot: a `401` from it reacting with
  /// another refresh would wait on itself forever, and a timeout raising the
  /// retry dialog would block boot on the user's answer. It fails fast
  /// instead, and the caller decides.
  @POST(AuthApiConstants.REFRESH_TOKEN)
  @Extra({
    NetworkConstants.EXTRA_CAN_REFRESH_TOKEN: false,
    NetworkConstants.EXTRA_CAN_RETRY: false,
  })
  Future<BaseEntity<UserModel>> refreshToken();
}
