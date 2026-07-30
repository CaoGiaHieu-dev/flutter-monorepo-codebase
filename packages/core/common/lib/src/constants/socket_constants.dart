/// A utility class for holding socket/WebSocket-related constants.
/// This class is not meant to be instantiated.
class SocketConstants {
  /// Private constructor to prevent instantiation of this class.
  SocketConstants._();

  // Socket events
  static const String CONNECT = 'connect';
  static const String DISCONNECT = 'disconnect';
  static const String MESSAGE = 'message';
  static const String TYPING = 'typing';
  static const String STOP_TYPING = 'stop_typing';
  static const String USER_JOINED = 'user_joined';
  static const String USER_LEFT = 'user_left';
}
