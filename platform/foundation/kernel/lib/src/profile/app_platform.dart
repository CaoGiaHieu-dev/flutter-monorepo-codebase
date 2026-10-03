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

  /// Whether `http_security_pinning` has a native side here: only Android and
  /// iOS install a pinned `HttpClient`. On the web the browser owns TLS, and
  /// the plugin has no desktop implementation — pinning a desktop build would
  /// route every HTTPS call through a plugin that cannot serve it.
  bool get canPinTls => this == android || this == ios;

  /// Windows, macOS and Linux — the platforms with a resizable window.
  bool get isDesktop => this == windows || this == macos || this == linux;
}
