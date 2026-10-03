/// Values passed in with `--dart-define-from-file=apps/<id>/env.<flavor>`.
///
/// Only keys Dart actually reads are declared here. A key the native side
/// consumes alone (`WEB_DOMAIN` and `APP_LINK_MODE`, read by Gradle and the iOS
/// entitlements) stays in the env file without an entry.
class EnvConstants {
  EnvConstants._();

  /// The base URL for all API endpoints.
  static const String BASE_URL = String.fromEnvironment('BASE_URL');

  /// The name of the application.
  static const String APP_NAME = String.fromEnvironment('APP_NAME');
}
