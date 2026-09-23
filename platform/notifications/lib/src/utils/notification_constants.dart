/// Constants owned exclusively by `core_notifications`.
///
/// These live here — not in `platform_kernel` — so no other package can read or
/// depend on this package's channel configuration. Every value is the
/// physical identifier registered with the OS: changing a channel id or group
/// id orphans the channel already created on a user's device, so treat these
/// strings as a migration-sensitive contract.
class NotificationConstants {
  /// Private constructor to prevent instantiation of this class.
  NotificationConstants._();

  static const String CHANNEL_ID = 'message_channel';
  static const String CHANNEL_NAME = 'Message';
  static const String CHANNEL_DESCRIPTION = 'You have a message.';
  static const String CHANNEL_GROUP_ID = 'com.message.group.notify';
  static const String CHANNEL_GROUP_NAME = 'Message';
  static const String CHANNEL_GROUP_DESCRIPTION = 'You have a message.';
  static const String ANDROID_DEFAULT_ICON = '@mipmap/ic_launcher_round';
}
