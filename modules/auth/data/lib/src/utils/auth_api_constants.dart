/// REST endpoints owned exclusively by `feature_auth`'s data layer.
///
/// Package-internal by convention — no other package's pubspec declares a
/// dependency on `data_auth`, so nothing outside this package can reach
/// [AuthRemoteDataSource] (or these paths) even though the barrel re-exports
/// them. Never reference these endpoints from another package.
///
/// Two constants, because the sample calls two endpoints. Register, forgot
/// password, reset password and the profile endpoints were declared here with
/// nothing routing to them.
class AuthApiConstants {
  AuthApiConstants._();

  static const String LOGIN = '/user/login';
  static const String REFRESH_TOKEN = '/user/refresh-token';
}
