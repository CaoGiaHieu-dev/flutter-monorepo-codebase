import 'dart:io';

import 'package:dynamic_logger/dynamic_logger.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:http_security_pinning/http_security_pinning.dart';

import '../../core_common.dart';

/// Orchestrates all app-wide service initializations.
///
/// This cleanly decouples initialization concerns (DI, logger, system themes, orientation)
/// from the entrypoint `main.dart` script.
class AppInitializer {
  AppInitializer._();

  /// Performs all required startup initializations.
  static Future<void> init({RouteObserver<ModalRoute>? routeObserver}) async {
    // Global setup for operations (e.g., error handling, logging)
    _setupOperationGlobalConfig();

    // Configure Dynamic Logger
    _setupDynamicLogger();

    // Override HTTP settings to allow bad certificates (for development purposes)
    _setupHttpOverrides();

    // Enable URL reflection for imperative APIs in GoRouter
    GoRouter.optionURLReflectsImperativeAPIs = true;

    // Initialize App Information Helper
    AppInfoHelper.initialize();

    // Connect route observer to RouteAwareWidget if provided
    if (routeObserver != null) {
      RouteAwareWidget.observer = routeObserver;
    }

    // Configure System Settings (Orientation & UI Overlay)
    await _configureSystemSettings();
  }

  static void _setupOperationGlobalConfig() {
    // OperationGlobalConfig.instance.setup(
    //   onFailure: (failure) {
    //     AppDialog.showErrorDialog(title: 'Error', message: failure.message);
    //   },
    // );
  }

  static void _setupDynamicLogger() {
    DynamicLogger.configure(
      truncate: true,
      maxDepth: 20,
      maxCollectionEntries: 50,
    );
  }

  static void _setupHttpOverrides() {
    if (AppConfig.appFlavor == Flavor.dev) {
      // Bypass certificate validation only in Development flavor for local testing.
      HttpOverrides.global = _MyHttpOverrides();
    } else {
      // Apply Global SSL Certificate Pinning via HttpSecurityPinningClient on Staging and Production.
      // This automatically secures all HttpClients in the entire application (including Dio, Image loaders, WebSockets, etc.)
      final hashes = getItOrNull<SslPinningConfig>()?.sslPinningHashes;
      if (hashes?.isNotEmpty == true) {
        HttpOverrides.global = _MyHttpSecurityPinningHttpOverrides(hashes!);
      }
    }
  }

  static Future<void> _configureSystemSettings() async {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
  }
}

class _MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (
        X509Certificate cert,
        String host,
        int port,
      ) => true;
  }
}

class _MyHttpSecurityPinningHttpOverrides extends HttpOverrides {
  final List<String> pins;
  _MyHttpSecurityPinningHttpOverrides(this.pins);

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return HttpSecurityPinningClient(pins);
  }
}
