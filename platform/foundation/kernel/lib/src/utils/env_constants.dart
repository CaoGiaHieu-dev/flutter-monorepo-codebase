/// Values passed in with `--dart-define-from-file=apps/<id>/env.<flavor>`.
///
/// Only keys Dart actually reads are declared here. A key the native side
/// consumes alone (`APP_LINK_MODE`, read by the iOS entitlements) stays in the
/// env file without an entry.
class EnvConstants {
  EnvConstants._();

  /// The base URL for all API endpoints.
  static const String BASE_URL = String.fromEnvironment('BASE_URL');

  /// The web domain whose links open the app (universal / app links).
  static const String WEB_DOMAIN = String.fromEnvironment('WEB_DOMAIN');

  /// The name of the application.
  static const String APP_NAME = String.fromEnvironment('APP_NAME');
}
