/// Constants owned exclusively by `core_notifications`.
///
/// These live here — not in `core_common` — so no other package can read or
/// depend on this package's channel configuration. Every value is the
/// physical identifier registered with the OS: changing a channel id or group
/// id orphans the channel already created on a user's device, so treat these
/// strings as a migration-sensitive contract.
class NotificationConstants {
  /// Private constructor to prevent instantiation of this class.
  NotificationConstants._();

  // ---------------------------------------------------------------------------
  // Active push notification channel (used by PushNotificationService)
  // ---------------------------------------------------------------------------

  static const String channelId = 'message_channel';
  static const String channelName = 'Message';
  static const String channelDescription = 'You have a message.';
  static const String channelGroupId = 'com.message.group.notify';
  static const String channelGroupName = 'Message';
  static const String channelGroupDescription = 'You have a message.';
  static const String androidDefaultIcon = '@mipmap/ic_launcher_round';

  // ---------------------------------------------------------------------------
  // Reference channel ids / payload types — sample scaffolding.
  //
  // Nothing in the template reads these yet. They illustrate how an app would
  // segment channels and branch on `message.data['type']`. Delete them, or
  // wire them into `PushNotificationService`, when defining real channels.
  // ---------------------------------------------------------------------------

  static const String DEFAULT_CHANNEL_ID = 'default_channel';
  static const String CHAT_CHANNEL_ID = 'chat_channel';
  static const String SYSTEM_CHANNEL_ID = 'system_channel';

  static const String MESSAGE_NOTIFICATION = 'message';
  static const String SYSTEM_NOTIFICATION = 'system';
  static const String UPDATE_NOTIFICATION = 'update';
}
