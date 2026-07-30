library core.constants;

/// A utility class for holding analytics-related constants.
/// This class is not meant to be instantiated.
class AnalyticsConstants {
  /// Private constructor to prevent instantiation of this class.
  AnalyticsConstants._();

  // Event names
  static const String USER_LOGIN = 'user_login';
  static const String USER_LOGOUT = 'user_logout';
  static const String USER_REGISTER = 'user_register';
  static const String SCREEN_VIEW = 'screen_view';
  static const String BUTTON_CLICK = 'button_click';

  // Parameter names
  static const String USER_ID = 'user_id';
  static const String SCREEN_NAME = 'screen_name';
  static const String BUTTON_NAME = 'button_name';
}
