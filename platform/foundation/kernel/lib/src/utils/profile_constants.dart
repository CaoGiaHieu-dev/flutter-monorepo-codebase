/// Build-time switches of the app profile, read from `--dart-define`.
class ProfileConstants {
  ProfileConstants._();

  /// `--dart-define=ALLOW_UNDECLARED_PLATFORM=true` lets an app start on a
  /// platform its manifest does not declare — a developer's quick look on a
  /// laptop — instead of stopping at the boot-error screen (`P01`).
  ///
  /// The platform then behaves as the template did before apps could declare
  /// one (`PlatformFacts.today()`), and the shell logs a warning naming the
  /// manifest key to add.
  static const bool ALLOW_UNDECLARED_PLATFORM = bool.fromEnvironment(
    'ALLOW_UNDECLARED_PLATFORM',
  );
}
