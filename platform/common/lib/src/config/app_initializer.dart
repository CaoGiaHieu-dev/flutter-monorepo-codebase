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
      //
      // Requires `SslPinningConfig` to be registered in GetIt. Registering only
      // the `NetworkConfig` subtype is not enough — GetIt resolves by exact
      // type — which is why the app shell binds it explicitly in
      // `app/lib/di/network_binding_module.dart`.
      final config = getItOrNull<SslPinningConfig>();
      final hashes = config?.sslPinningHashes;

      if (hashes != null && hashes.isNotEmpty) {
        HttpOverrides.global = _MyHttpSecurityPinningHttpOverrides(hashes);
      } else {
        // Never fail silently here: without pinning the app still talks to the
        // server over plain TLS, so a proxy with a trusted root can read every
        // request. Surfacing it keeps a misconfiguration from shipping unnoticed.
        DynamicLogger.log(
          config == null
              ? 'SSL pinning skipped: no SslPinningConfig registered in GetIt. '
                    'Traffic on ${AppConfig.appFlavor.name} is NOT pinned.'
              : 'SSL pinning skipped: sslPinningHashes is empty. '
                    'Traffic on ${AppConfig.appFlavor.name} is NOT pinned.',
          tag: 'Security',
          level: LogLevel.ERROR,
        );
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
