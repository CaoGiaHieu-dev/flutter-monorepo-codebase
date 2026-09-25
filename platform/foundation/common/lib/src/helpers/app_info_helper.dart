import 'package:dynamic_logger/dynamic_logger.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Helper class for retrieving application information.
///
/// This singleton class provides easy access to app metadata through the
/// package_info_plus package. It must be initialized before use to load the
/// necessary information.
///
/// Example usage:
/// ```dart
/// // Initialize during app startup
/// await AppInfoHelper.initialize();
///
/// // Get app information
/// final version = AppInfoHelper.instance.fullVersion;
/// ```
class AppInfoHelper {
  static AppInfoHelper? _instance;

  /// Gets the singleton instance of [AppInfoHelper].
  static AppInfoHelper get instance => _instance ??= AppInfoHelper._();

  /// Private constructor for singleton pattern.
  AppInfoHelper._();

  PackageInfo? _packageInfo;

  /// Initializes the helper by loading package information.
  ///
  /// This method must be called before accessing any app information.
  ///
  /// Should be called during app startup, typically in main() or app initialization.
  ///
  /// Never throws: `AppInitializer` starts it without awaiting, so a platform
  /// failure (no plugin in a unit test, an unsupported platform) is logged and
  /// the getters keep their fallback values instead of surfacing as an
  /// uncaught error.
  static Future<void> initialize() async {
    // Through [instance], not `_instance?`: the singleton does not exist yet
    // on the first call, and writing through a null-aware access silently
    // dropped the loaded info.
    final helper = instance;
    try {
      helper._packageInfo = await PackageInfo.fromPlatform();
    } catch (e) {
      DynamicLogger.log(
        'Package info unavailable (${e.runtimeType}); using fallbacks.',
        tag: 'AppInfoHelper',
        level: LogLevel.WARNING,
      );
    }
  }

  /// Gets the application name as defined in the platform configuration.
  ///
  /// Returns 'Unknown' if package information is not available.
  String get appName => _packageInfo?.appName ?? 'Unknown';

  /// Gets the application package name (bundle identifier).
  ///
  /// Returns 'Unknown' if package information is not available.
  String get packageName => _packageInfo?.packageName ?? 'Unknown';

  /// Gets the application version string.
  ///
  /// Returns '0.0.0' if package information is not available.
  String get version => _packageInfo?.version ?? '0.0.0';

  /// Gets the application build number.
  ///
  /// Returns '0' if package information is not available.
  String get buildNumber => _packageInfo?.buildNumber ?? '0';

  /// Gets the full version string combining version and build number.
  ///
  /// Format: "version+buildNumber" (e.g., "1.2.3+45")
  String get fullVersion => '$version+$buildNumber';

  /// Gets app information as a formatted string for debugging.
  ///
  /// Returns a multi-line string containing app name, package and version.
  /// Useful for debug logs and crash reports.
  String getDebugInfo() {
    return '''
App Name: $appName
Package: $packageName
Version: $fullVersion
''';
  }

  /// Gets app information as a structured map.
  ///
  /// Returns a map containing all app metadata including name, package,
  /// and version information. Useful for analytics and logging.
  Map<String, dynamic> getAppInfo() {
    return {
      'appName': appName,
      'packageName': packageName,
      'version': version,
      'buildNumber': buildNumber,
      'fullVersion': fullVersion,
    };
  }
}
