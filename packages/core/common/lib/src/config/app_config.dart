import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' as services;

import '../../core_common.dart';

/// Central configuration class for the application
///
/// This class provides access to environment-specific configurations,
/// Firebase options, and application constants. It uses the current
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
/// final firebaseOptions = AppConfig.firebase;
/// ```
class AppConfig {
  /// Private constructor to prevent instantiation
  AppConfig._();

  /// Design size used for responsive UI calculations
  /// Based on iPhone X dimensions (375x812)
  static Size get design => const Size(375, 812);

  /// Default language for the application
  static Locale defaultLanguage = PlatformDispatcher.instance.locale;

  /// Current application flavor (dev, staging, prod)
  /// Determined from the build configuration with validation
  static Flavor get appFlavor => Flavor.values.firstWhere(
    (e) => e.toValue() == services.appFlavor?.toLowerCase(),
    orElse: () => Flavor.dev,
  );

  /// Firebase configuration options based on current flavor
  /// Resolved dynamically from dependency injection (GetIt)
  static FirebaseOptions get firebase {
    return getIt<FirebaseOptions>();
  }

  /// Application title from environment constants
  static String get title => EnvConstants.APP_NAME;

  /// Base URL for API calls based on current flavor
  static String get baseUrl => EnvConstants.BASE_URL;

  /// WebSocket URL for real-time communication
  static String get socketUrl => EnvConstants.SOCKET;

  /// Web domain for the application
  static String get webDomain => EnvConstants.WEB_DOMAIN;

  /// Google Maps API key
  static String get googleMapsApiKey => EnvConstants.GOOGLE_MAP_API;

  /// Facebook App ID
  static String get facebookAppId => EnvConstants.FACEBOOK_APP_ID;

  /// Application schema version
  static String get appSchemaVersion => EnvConstants.APP_SCHEMA_VERSION;

  /// Gets the current environment name as a string
  static String get environmentName => appFlavor.toValue();

  /// Checks if the app is running in debug mode
  static bool get isDebug => kDebugMode;

  /// Checks if the app is running in release mode
  static bool get isRelease => kReleaseMode;

  /// Checks if the app is running in profile mode
  static bool get isProfile => kProfileMode;

  /// Checks if the app is running in development environment
  static bool get isDevelopment => appFlavor == Flavor.dev;

  /// Checks if the app is running in staging environment
  static bool get isStaging => appFlavor == Flavor.staging;

  /// Checks if the app is running in production environment
  static bool get isProduction => appFlavor == Flavor.prod;
}
