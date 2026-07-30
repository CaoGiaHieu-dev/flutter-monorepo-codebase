library core.constants;

/// A utility class for holding constants related to storage keys.
/// This class provides a centralized location for managing all storage keys,
/// ensuring consistency and reducing the risk of typos.
/// This class is not meant to be instantiated.
class StorageKeyConstants {
  /// Private constructor to prevent instantiation of this class.
  StorageKeyConstants._();

  /// The key for storing the user's preferred theme mode (e.g., light, dark).
  static const String THEME_MODE = 'themeMode';

  /// The key for storing the user's selected locale or language.
  static const String LOCALE = 'locale';

  /// The key for storing the authentication token.
  static const String TOKEN = 'token';

  /// The key for storing user authentication data.
  static const String AUTH_USER = 'auth_user';

  /// The key for storing the refresh token for re-authenticating the user.
  static const String REFRESH_TOKEN = 'auth_refresh_token';

  /// The key for storing session-related data.
  static const String AUTH_SESSION = 'auth_session';

  /// The key for tracking cache keys to manage cached data.
  static const String CACHE_KEYS_TRACKING = 'cache_keys_tracking';

  /// The key for tracking viewed onboard.
  static const String VIEWED_ONBOARD = 'viewed_onboard';
}
