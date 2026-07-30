library core.constants;

/// A utility class for holding API-related constants.
/// This class is not meant to be instantiated.
class ApiConstants {
  /// Private constructor to prevent instantiation of this class.
  ApiConstants._();

  // Authentication endpoints
  static const String LOGIN = '/user/login';
  static const String REGISTER = '/user/register';
  static const String REFRESH_TOKEN = '/user/refresh-token';
  static const String FORGOT_PASSWORD = '/user/forgot-password';
  static const String RESET_PASSWORD = '/user/reset-password';

  // User endpoints
  static const String USER_PROFILE = '/user/profile';
  static const String UPDATE_PROFILE = '/user/profile/update';

  // Common endpoints
  static const String HEALTH_CHECK = '/health';
}
