/// Build-time switches of the app profile, read from `--dart-define`.
class ProfileConstants {
  ProfileConstants._();

  /// `--dart-define=ALLOW_UNDECLARED_PLATFORM=true` lets an app start on a
  /// platform its manifest does not declare — a developer's quick look on a
  /// laptop — instead of stopping at the boot-error screen (`P01`).
  ///
  /// The platform then gets the template defaults
  /// (`PlatformFacts.today()`), and the shell logs a warning naming the
  /// manifest key to add.
  static const bool ALLOW_UNDECLARED_PLATFORM = bool.fromEnvironment(
    'ALLOW_UNDECLARED_PLATFORM',
  );

  /// `--dart-define=APP_FLAVOR=<dev|staging|prod>` names the flavor of a
  /// **web** build — the one target whose Flutter tool has no `--flavor`
  /// option. (The tool also refuses `--dart-define=FLUTTER_APP_FLAVOR=...`: that
  /// name is the framework's own.) Empty by default, and read on the web only:
  /// every other platform declares its flavor with `--flavor`.
  ///
  /// Without it a web build is `prod` in release and `dev` in debug, like any
  /// build that declared no flavor.
  static const String APP_FLAVOR = String.fromEnvironment('APP_FLAVOR');
}
