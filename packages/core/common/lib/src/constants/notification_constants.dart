library core.constants;

/// A utility class for holding push notification-related constants.
/// This class is not meant to be instantiated.
class NotificationConstants {
  /// Private constructor to prevent instantiation of this class.
  NotificationConstants._();

  // Notification channels
  static const String DEFAULT_CHANNEL_ID = 'default_channel';
  static const String CHAT_CHANNEL_ID = 'chat_channel';
  static const String SYSTEM_CHANNEL_ID = 'system_channel';

  // Notification types
  static const String MESSAGE_NOTIFICATION = 'message';
  static const String SYSTEM_NOTIFICATION = 'system';
  static const String UPDATE_NOTIFICATION = 'update';

  // Push notification config (from core_notifications)
  static const String channelId = 'message_channel';
  static const String channelName = 'Message';
  static const String channelDescription = 'You have a message.';
  static const String channelGroupId = 'com.message.group.notify';
  static const String channelGroupName = 'Message';
  static const String channelGroupDescription = 'You have a message.';
  static const String androidDefaultIcon = '@mipmap/ic_launcher_round';
}
