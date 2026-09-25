import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' as services;
import 'package:material_ui/material_ui.dart';
import 'package:platform_kernel/platform_kernel.dart';

/// Central configuration class for the application
///
/// This class provides access to environment-specific configurations
/// and application constants. It uses the current
/// app flavor to determine which configuration to use.
///
/// The configuration system includes:
/// - Environment detection and validation
/// - Configuration caching for performance
/// - Error handling for missing configurations
/// - Validation of required environment variables
///
/// Example usage:
/// ```dart
/// // Initialize configuration during app startup
/// await AppConfig.initialize();
///
/// // Access configuration values
/// final apiUrl = AppConfig.baseUrl;
/// final flavor = AppConfig.appFlavor;
/// ```
class AppConfig {
  /// Private constructor to prevent instantiation
  AppConfig._();

  /// Default language for the application
  static Locale defaultLanguage = PlatformDispatcher.instance.locale;

  /// The flavor the build declared (`--flavor`, i.e. `FLUTTER_APP_FLAVOR`),
  /// or `null` when it declared none or one this app does not know.
  ///
  /// Anything security-relevant must read this, not [appFlavor]: only an
  /// explicit declaration may relax a safeguard.
  static Flavor? get declaredFlavor => parseFlavor(services.appFlavor);

  /// Current application flavor (dev, staging, prod), used to pick the DI
  /// environment and per-flavor configuration.
  ///
  /// A build that declared no known flavor falls back per build mode — see
  /// [resolveFlavor]: `dev` in a debug build (so a plain `flutter run` of an
  /// app without flavors still works), `prod` otherwise.
  static Flavor get appFlavor =>
      resolveFlavor(services.appFlavor, isDebug: kDebugMode);

  /// Whether TLS certificate validation may be switched off.
  ///
  /// Only a **debug** build that **explicitly** declared the `dev` flavor
  /// qualifies — see [allowsCertificateBypass].
  static bool get bypassesCertificateValidation => allowsCertificateBypass(
    declaredFlavor: declaredFlavor,
    isDebug: kDebugMode,
  );

  /// Parses a raw flavor name (case-insensitive); `null` when [raw] is null
  /// or names no [Flavor].
  static Flavor? parseFlavor(String? raw) {
    final name = raw?.trim().toLowerCase();
    if (name == null || name.isEmpty) return null;
    for (final flavor in Flavor.values) {
      if (flavor.toValue() == name) return flavor;
    }
    return null;
  }

  /// The flavor for [raw], falling back to `dev` in a debug build and to
  /// `prod` in a profile or release build.
  ///
  /// Falling back to `dev` unconditionally meant a release built without a
  /// flavor — or with a misspelt one — ran as `dev`, and `dev` is the flavor
  /// that used to disable certificate validation. The fallback now fails
  /// closed outside debug; certificate handling additionally ignores the
  /// fallback altogether (see [allowsCertificateBypass]).
  static Flavor resolveFlavor(String? raw, {required bool isDebug}) =>
      parseFlavor(raw) ?? (isDebug ? Flavor.dev : Flavor.prod);

  /// The rule behind [bypassesCertificateValidation]: a debug build whose
  /// declared flavor is explicitly `dev`.
  ///
  /// A missing or unknown flavor is treated like `prod` here — it keeps
  /// validation on, even in debug — and a `dev` flavor in a profile or
  /// release build keeps it on too, so no build a user can install accepts
  /// an arbitrary certificate.
  static bool allowsCertificateBypass({
    required Flavor? declaredFlavor,
    required bool isDebug,
  }) => isDebug && declaredFlavor == Flavor.dev;

  /// Application title from environment constants
  static String get title => EnvConstants.APP_NAME;

  /// Base URL for API calls based on current flavor
  static String get baseUrl => EnvConstants.BASE_URL;
}
