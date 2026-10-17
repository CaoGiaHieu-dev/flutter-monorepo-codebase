/// A platform an app can run on — the closed vocabulary of
/// `platforms:` in `apps/<id>/app_manifest.yaml`.
///
/// Spelled by name, never by `dart:io` or Flutter: the kernel is pure Dart.
/// `resolveAppPlatform()` in `core_common` is the one place that maps the
/// running device onto one of these.
enum AppPlatform {
  android,
  ios,
  web,
  windows,
  macos,
  linux;

  /// Whether `http_security_pinning` can pin TLS here: every platform but the
  /// web. Android and iOS read the certificate chain through the plugin's
  /// native side (Android the chain the server sends, iOS the one its trust
  /// evaluation builds); Windows, macOS and Linux read the leaf certificate
  /// with a pure-Dart probe (`dart:io` exposes no chain), so a desktop pin set
  /// must contain the leaf's key. On the web the browser owns TLS, and the
  /// package's web client verifies signed responses instead, which is not
  /// pinning. (The package's own `isSupported` answers for the platform the
  /// code runs on, not for one an app declares, and the kernel names no
  /// package.)
  bool get canPinTls =>
      this == android ||
      this == ios ||
      this == windows ||
      this == macos ||
      this == linux;

  /// Windows, macOS and Linux — the platforms with a resizable window.
  bool get isDesktop => this == windows || this == macos || this == linux;
}
