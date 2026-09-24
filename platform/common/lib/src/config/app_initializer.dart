import 'dart:io';

import 'package:core_responsive/core_responsive.dart';
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

    // Certificate handling: pinning, or — debug + explicit dev flavor only —
    // a bypass for local self-signed servers.
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
    // Fail closed. Validation is switched off only for a debug build that
    // explicitly declared the `dev` flavor; a missing or unknown flavor is
    // treated as `prod` here. `appFlavor` used to fall back to `dev`, so a
    // build without `--flavor` — release included — accepted any
    // certificate.
    if (AppConfig.bypassesCertificateValidation) {
      DynamicLogger.log(
        'TLS certificate validation is DISABLED (debug build, dev flavor). '
        'Every certificate is accepted.',
        tag: 'Security',
        level: LogLevel.WARNING,
      );
      HttpOverrides.global = _MyHttpOverrides();
      return;
    }

    final declared = AppConfig.declaredFlavor;
    if (declared == null) {
      DynamicLogger.log(
        'FLUTTER_APP_FLAVOR is missing or unknown ("$appFlavor"). Treating '
        'the build as prod for TLS: certificate validation stays ON. Pass '
        '--flavor dev to allow self-signed certificates in a debug build.',
        tag: 'Security',
        level: LogLevel.ERROR,
      );
    } else if (declared == Flavor.dev) {
      DynamicLogger.log(
        'dev flavor in a non-debug build: the certificate bypass is '
        'debug-only, so certificate validation stays ON.',
        tag: 'Security',
        level: LogLevel.WARNING,
      );
    }

    // Apply Global SSL Certificate Pinning via HttpSecurityPinningClient.
    // This automatically secures all HttpClients in the entire application
    // (including Dio, Image loaders, WebSockets, etc.)
    //
    // Requires `SslPinningConfig` to be registered in GetIt. Registering only
    // the `NetworkConfig` subtype is not enough — GetIt resolves by exact
    // type — which is why the app shell binds it explicitly in
    // `platform/app_shell/lib/di/network_binding_module.dart`.
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

  static Future<void> _configureSystemSettings() async {
    await SystemChrome.setPreferredOrientations(
      preferredOrientationsFor(_shortestSideAtLaunch()),
    );
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
  }

  /// The orientations to allow on a display whose shortest side is
  /// [shortestSide] logical pixels (`null` when it could not be measured).
  ///
  /// A phone-sized display (shortest side below the Material 3 `medium`
  /// breakpoint, 600) is locked to portrait: the phone layouts are designed
  /// for it. Anything larger — a tablet, an unfolded foldable, a desktop —
  /// gets every orientation (an empty list means "no preference"), so it is
  /// never letterboxed and its landscape and rail layouts are reachable.
  /// Locking every device to portrait did both. An unmeasurable display is
  /// left unlocked too, rather than guessed to be a phone.
  ///
  /// This is a device question — whether to lock at all — so it is decided
  /// once from the display at launch. Layout still follows the window size
  /// class, never this.
  static List<DeviceOrientation> preferredOrientationsFor(
    double? shortestSide,
  ) {
    if (shortestSide == null) return const [];
    final phoneSized = shortestSide < const ResponsiveBreakpoints().medium;
    return phoneSized ? const [DeviceOrientation.portraitUp] : const [];
  }

  /// Shortest side, in logical pixels, of the display the first view is on
  /// — or of the view itself when the display reports no size. `null` when
  /// neither is known yet.
  ///
  /// The display, not the window: a tablet launched into a narrow
  /// split-screen pane is still a tablet and must not be locked.
  static double? _shortestSideAtLaunch() {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) return null;
    final view = views.first;

    Size? logical(Size physical, double ratio) =>
        physical.isEmpty || ratio <= 0 ? null : physical / ratio;

    Size? size;
    try {
      final display = view.display;
      size = logical(display.size, display.devicePixelRatio);
    } catch (_) {
      // Some embedders expose no display for a view.
    }
    size ??= logical(view.physicalSize, view.devicePixelRatio);
    return size?.shortestSide;
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
