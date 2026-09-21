import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Helper class for retrieving application and device information.
///
/// This singleton class provides easy access to app metadata and device
/// information using the package_info_plus and device_info_plus packages.
/// It must be initialized before use to load the necessary information.
///
/// Features:
/// - App version and build information
/// - Device model and platform details
/// - Debug information formatting
/// - Physical device detection
///
/// Example usage:
/// ```dart
/// // Initialize during app startup
/// await AppInfoHelper.instance.initialize();
///
/// // Get app information
/// final version = AppInfoHelper.instance.fullVersion;
/// final deviceInfo = await AppInfoHelper.instance.getDeviceInfo();
/// ```
class AppInfoHelper {
  static AppInfoHelper? _instance;

  /// Gets the singleton instance of [AppInfoHelper].
  static AppInfoHelper get instance => _instance ??= AppInfoHelper._();

  /// Private constructor for singleton pattern.
  AppInfoHelper._();

  PackageInfo? _packageInfo;
  DeviceInfoPlugin? _deviceInfo;

  /// Initializes the helper by loading package and device information.
  ///
  /// This method must be called before accessing any app or device information.
  /// It loads the package information from the platform and initializes the
  /// device info plugin.
  ///
  /// Should be called during app startup, typically in main() or app initialization.
  static Future<void> initialize() async {
    _instance?._packageInfo = await PackageInfo.fromPlatform();
    _instance?._deviceInfo = DeviceInfoPlugin();
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

  /// Gets comprehensive device information as a map.
  ///
  /// Returns platform-specific device information including model, manufacturer,
  /// OS version, and other relevant details. The structure varies by platform.
  ///
  /// Throws [StateError] if the helper hasn't been initialized.
  ///
  /// Returns a map containing:
  /// - platform: The platform name (Android/iOS/Unknown)
  /// - model: Device model name
  /// - manufacturer: Device manufacturer (Android only)
  /// - version: OS version information
  /// - isPhysicalDevice: Whether running on physical hardware
  /// - Additional platform-specific fields
  Future<Map<String, dynamic>> getDeviceInfo() async {
    if (_deviceInfo == null) {
      throw StateError(
        'AppInfoHelper not initialized. Call initialize() first.',
      );
    }

    if (Platform.isAndroid) {
      final androidInfo = await _deviceInfo!.androidInfo;
      return {
        'platform': 'Android',
        'model': androidInfo.model,
        'manufacturer': androidInfo.manufacturer,
        'version': androidInfo.version.release,
        'sdkInt': androidInfo.version.sdkInt,
        'brand': androidInfo.brand,
        'device': androidInfo.device,
        'id': androidInfo.id,
        'isPhysicalDevice': androidInfo.isPhysicalDevice,
      };
    } else if (Platform.isIOS) {
      final iosInfo = await _deviceInfo!.iosInfo;
      return {
        'platform': 'iOS',
        'model': iosInfo.model,
        'name': iosInfo.name,
        'systemName': iosInfo.systemName,
        'systemVersion': iosInfo.systemVersion,
        'localizedModel': iosInfo.localizedModel,
        'identifierForVendor': iosInfo.identifierForVendor,
        'isPhysicalDevice': iosInfo.isPhysicalDevice,
      };
    }

    return {'platform': 'Unknown'};
  }

  /// Gets a human-readable device string for display purposes.
  ///
  /// Returns a formatted string containing device model and OS version
  /// information suitable for showing to users or in logs.
  ///
  /// Example outputs:
  /// - "Samsung Galaxy S21 (Android 12)"
  /// - "John's iPhone (iOS 15.4)"
  /// - "Unknown Device" (for unsupported platforms)
  Future<String> getDeviceString() async {
    final deviceInfo = await getDeviceInfo();

    if (Platform.isAndroid) {
      return '${deviceInfo['manufacturer']} ${deviceInfo['model']} (Android ${deviceInfo['version']})';
    } else if (Platform.isIOS) {
      return '${deviceInfo['name']} (${deviceInfo['systemName']} ${deviceInfo['systemVersion']})';
    }

    return 'Unknown Device';
  }

  /// Checks if the app is running on a physical device.
  ///
  /// Returns true if running on actual hardware, false if running
  /// on an emulator or simulator. Useful for debugging and analytics.
  Future<bool> isPhysicalDevice() async {
    final deviceInfo = await getDeviceInfo();
    return deviceInfo['isPhysicalDevice'] ?? false;
  }

  /// Gets the current platform name.
  ///
  /// Returns a string identifying the current platform:
  /// Android, iOS, Windows, macOS, Linux, or Unknown.
  String get platformName {
    if (Platform.isAndroid) return 'Android';
    if (Platform.isIOS) return 'iOS';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isLinux) return 'Linux';
    return 'Unknown';
  }

  /// Gets app information as a formatted string for debugging.
  ///
  /// Returns a multi-line string containing app name, package, version,
  /// and platform information. Useful for debug logs and crash reports.
  String getDebugInfo() {
    return '''
App Name: $appName
Package: $packageName
Version: $fullVersion
Platform: $platformName
''';
  }

  /// Gets app information as a structured map.
  ///
  /// Returns a map containing all app metadata including name, package,
  /// version information, and platform. Useful for analytics and logging.
  Map<String, dynamic> getAppInfo() {
    return {
      'appName': appName,
      'packageName': packageName,
      'version': version,
      'buildNumber': buildNumber,
      'fullVersion': fullVersion,
      'platform': platformName,
    };
  }
}
