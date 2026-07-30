library core.constants;

/// A utility class for holding Firebase Remote Config-related constants.
/// This class is not meant to be instantiated.
class FirebaseRemoteConfigConstants {
  /// Private constructor to prevent instantiation of this class.
  FirebaseRemoteConfigConstants._();

  // Remote config keys
  static const String FEATURE_FLAGS = 'feature_flags';
  static const String APP_VERSION_CONFIG = 'app_version_config';
  static const String MAINTENANCE_MODE = 'maintenance_mode';
}
