/// REST endpoints owned exclusively by `feature_auth`'s data layer.
///
/// Package-internal by convention — no other package's pubspec declares a
/// dependency on `data_auth`, so nothing outside this package can reach
/// [AuthRemoteDataSource] (or these paths) even though the barrel re-exports
/// them. Never reference these endpoints from another package.
class AuthApiConstants {
  AuthApiConstants._();

  static const String LOGIN = '/user/login';
  static const String REGISTER = '/user/register';
  static const String REFRESH_TOKEN = '/user/refresh-token';
  static const String FORGOT_PASSWORD = '/user/forgot-password';
  static const String RESET_PASSWORD = '/user/reset-password';
  static const String USER_PROFILE = '/user/profile';
  static const String UPDATE_PROFILE = '/user/profile/update';
}
