library core.constants;

/// A utility class for holding environment-specific constants.
/// These constants are loaded from the build configuration and may vary between
/// different environments (e.g., development, staging, production).
/// This class is not meant to be instantiated.
class EnvConstants {
  /// Private constructor to prevent instantiation of this class.
  EnvConstants._();

  /// The API key for accessing Google Maps services.
  static const String GOOGLE_MAP_API = String.fromEnvironment('GOOGLE_MAP_API');

  /// The App ID for Facebook integration (e.g., for social login).
  static const String FACEBOOK_APP_ID = String.fromEnvironment(
    'FACEBOOK_APP_ID',
  );

  /// The token for accessing Facebook services.
  static const String FACEBOOK_TOKEN = String.fromEnvironment('FACEBOOK_TOKEN');

  /// The configuration for Google services.
  static const String GOOGLE_APP = String.fromEnvironment('GOOGLE_APP');

  /// The base URL for all API endpoints.
  static const String BASE_URL = String.fromEnvironment('BASE_URL');

  /// The URL for the WebSocket server.
  static const String SOCKET = String.fromEnvironment('SOCKET');

  /// The web domain for the application.
  static const String WEB_DOMAIN = String.fromEnvironment('WEB_DOMAIN');

  /// The version of the application schema.
  static const String APP_SCHEMA_VERSION = String.fromEnvironment(
    'APP_SCHEMA_VERSION',
  );

  /// The name of the application.
  static const String APP_NAME = String.fromEnvironment('APP_NAME');
}
