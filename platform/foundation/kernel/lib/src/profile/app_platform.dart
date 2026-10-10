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
  /// web. Android and iOS read the whole certificate chain through the
  /// plugin's native side; Windows, macOS and Linux read the leaf certificate
  /// with a pure-Dart probe (`dart:io` exposes no chain), so a desktop pin set
  /// must contain the leaf's key. On the web the browser owns TLS, and the
  /// package's web client verifies signed responses instead, which is not
  /// pinning. (The package's own `isSupported` is true everywhere, so it
  /// cannot answer this.)
  bool get canPinTls =>
      this == android ||
      this == ios ||
      this == windows ||
      this == macos ||
      this == linux;

  /// Windows, macOS and Linux — the platforms with a resizable window.
  bool get isDesktop => this == windows || this == macos || this == linux;
}
