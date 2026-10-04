import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' as services;
import 'package:material_ui/material_ui.dart';
import 'package:platform_kernel/platform_kernel.dart';

import 'platform_resolver.dart';

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
  static Flavor? get declaredFlavor => parseFlavor(
    declaredFlavorName(
      toolFlavor: services.appFlavor,
      webDefine: ProfileConstants.APP_FLAVOR,
      isWeb: resolveAppPlatform() == AppPlatform.web,
    ),
  );

  /// The flavor name a build declared: the Flutter tool's own
  /// ([toolFlavor], `--flavor`) when there is one, else — on the web only,
  /// whose tool has no `--flavor` — the `--dart-define=APP_FLAVOR=<name>`
  /// ([webDefine]). `null` when the build declared none.
  ///
  /// The define never overrides a flavor the tool set, and is ignored off the
  /// web: a native build that names its flavor twice has one source of truth.
  @visibleForTesting
  static String? declaredFlavorName({
    required String? toolFlavor,
    required String webDefine,
    required bool isWeb,
  }) {
    if (toolFlavor != null && toolFlavor.trim().isNotEmpty) return toolFlavor;
    if (isWeb && webDefine.trim().isNotEmpty) return webDefine;
    return null;
  }

  /// Current application flavor (dev, staging, prod), used to pick the DI
  /// environment and per-flavor configuration.
  ///
  /// A build that declared no known flavor falls back per build mode — see
  /// [resolveFlavor]: `dev` in a debug build (so a plain `flutter run` of an
  /// app without flavors still works), `prod` otherwise.
  static Flavor get appFlavor => resolveFlavor(
    declaredFlavorName(
      toolFlavor: services.appFlavor,
      webDefine: ProfileConstants.APP_FLAVOR,
      isWeb: resolveAppPlatform() == AppPlatform.web,
    ),
    isDebug: kDebugMode,
  );

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
  /// Falling back to `dev` unconditionally would run a release built without
  /// a flavor — or with a misspelt one — as `dev`, the flavor that disables
  /// certificate validation. The fallback therefore fails closed outside
  /// debug; certificate handling additionally ignores the fallback
  /// altogether (see [allowsCertificateBypass]).
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

  /// The title the user sees for the app (the `MaterialApp` title, the window
  /// and task-switcher label).
  ///
  /// The per-flavor display name `APP_NAME` from the env file when the build
  /// defines it (`Codebase (DEV)`, `Codebase (STG)`) — that is how a flavor
  /// tells itself apart on a device — else [appName], the app's own name
  /// (`app.name` in its manifest, carried by `AppFacts.name`), else empty.
  /// So `app.name` is what the app is called, and `APP_NAME` is the per-flavor
  /// override of it.
  static String titleFor(String? appName) {
    const flavorName = EnvConstants.APP_NAME;
    if (flavorName.isNotEmpty) return flavorName;
    return appName ?? '';
  }

  /// Base URL for API calls based on current flavor
  static String get baseUrl => EnvConstants.BASE_URL;
}
