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

  /// Also named by `com.google.firebase.messaging.default_notification_channel_id`
  /// in each app's `AndroidManifest.xml` — change both together.
  static const String CHANNEL_ID = 'message_channel';
  static const String CHANNEL_NAME = 'Message';
  static const String CHANNEL_DESCRIPTION = 'You have a message.';
  static const String CHANNEL_GROUP_ID = 'com.message.group.notify';
  static const String CHANNEL_GROUP_NAME = 'Message';
  static const String CHANNEL_GROUP_DESCRIPTION = 'You have a message.';

  /// Small icon of every notification this package shows on Android.
  ///
  /// A drawable resource **name**, without the `@drawable/` prefix:
  /// flutter_local_notifications resolves it with
  /// `Resources.getIdentifier(name, "drawable", ...)`. The status bar draws
  /// only its alpha channel, so it must be a white-on-transparent glyph — a
  /// full-colour launcher icon renders as a solid square. Each app ships it
  /// per flavor (`apps/mobile/android/app/src/<flavor>/res/drawable-*/`),
  /// keeps it from the release resource shrinker (`res/raw/keep.xml`), and
  /// points FCM's `default_notification_icon` manifest entry at the same
  /// drawable, so background and foreground notifications look alike.
  static const String ANDROID_DEFAULT_ICON = 'ic_notification';
}
