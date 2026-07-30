import 'package:core_common/core_common.dart';
import 'package:dio/dio.dart';
import 'package:domain_core/domain_core.dart';
import 'package:retrofit/retrofit.dart';

import '../../models/user/user_model.dart';

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

  /// Authenticates user with provided credentials
  @POST(ApiConstants.LOGIN)
  Future<BaseEntity<UserModel>> login(@Body() Map<String, dynamic> loginData);

  /// Refreshes the current authentication token
  @POST(ApiConstants.REFRESH_TOKEN)
  Future<BaseEntity<UserModel>> refreshToken();
}
