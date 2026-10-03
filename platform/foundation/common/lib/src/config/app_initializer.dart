import 'dart:async';
import 'dart:io';

import 'package:dynamic_logger/dynamic_logger.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:http_security_pinning/http_security_pinning.dart';
import 'package:platform_kernel/platform_kernel.dart';

import '../go_route_data_custom.dart';
import '../helpers/app_info_helper.dart';
import 'app_config.dart';

/// Orchestrates all app-wide service initializations.
///
/// This cleanly decouples initialization concerns (DI, logger, system themes, orientation)
/// from the entrypoint `main.dart` script.
class AppInitializer {
  AppInitializer._();

  static bool _ranBeforeRunApp = false;

  /// The synchronous steps that must be in place before the first widget is
  /// built: logger configuration and the certificate handling
  /// ([HttpOverrides.global] — pinning, or, in a debug build that declared
  /// the `dev` flavor only, a bypass for local self-signed servers).
  ///
  /// `runShellApp` calls this right after dependency injection and **before**
  /// `MainScope` builds the splash. It cannot wait for [init]: the splash is
  /// already wrapped in every feature's `IAppTreeWrapper`, so a controller
  /// created there can open its first connection while [init] is still
  /// pending — and Dio's `IOHttpClientAdapter` keeps the `HttpClient` it
  /// created first, so that connection's client (unpinned) would serve the
  /// whole session.
  ///
  /// With the app's [profile], the [platform] this run is on and the [flavor]
  /// it is built as (what `runShellApp` passes; the flavor defaults to
  /// [AppConfig.appFlavor]), certificate pinning follows the app's declared
  /// decision for the flavor ([SslPinningPolicy]): pinned installs the
  /// pinning client, disabled logs its reason, and a platform that cannot pin
  /// TLS (`AppPlatform.canPinTls`: the web, where the browser owns TLS, and
  /// the desktop, where the pinning plugin has no implementation) says so once
  /// instead of installing or complaining. Without them the behaviour is the
  /// one before apps could declare it: pin whatever the registered
  /// `SslPinningConfig` lists, and log an ERROR when it lists none.
  ///
  /// Idempotent: [init] calls it too, for a host that never called it, and a
  /// second call installs nothing.
  static void initBeforeRunApp({
    AppProfile? profile,
    AppPlatform? platform,
    Flavor? flavor,
  }) {
    if (_ranBeforeRunApp) return;
    _ranBeforeRunApp = true;

    // Configure Dynamic Logger
    _setupDynamicLogger();

    // Certificate handling: pinning, or — debug + explicit dev flavor only —
    // a bypass for local self-signed servers.
    _setupHttpOverrides(
      profile,
      platform ?? (_isWeb ? AppPlatform.web : null),
      flavor ?? AppConfig.appFlavor,
    );
  }

  /// Lets a test run [initBeforeRunApp] again.
  @visibleForTesting
  static void debugResetBeforeRunApp() => _ranBeforeRunApp = false;

  /// Stands in for [kIsWeb] in a test, which always runs on the VM. `null`
  /// (the default) reads the real constant.
  @visibleForTesting
  static bool? debugIsWebOverride;

  static bool get _isWeb => debugIsWebOverride ?? kIsWeb;

  /// Performs all required startup initializations.
  static Future<void> init({
    RouteObserver<ModalRoute<void>>? routeObserver,
    AppProfile? profile,
    AppPlatform? platform,
    Flavor? flavor,
  }) async {
    // Logger + HttpOverrides. Normally already done by `runShellApp`, before
    // the splash was built; a no-op then.
    initBeforeRunApp(profile: profile, platform: platform, flavor: flavor);

    // Enable URL reflection for imperative APIs in GoRouter
    GoRouter.optionURLReflectsImperativeAPIs = true;

    // Initialize App Information Helper. Not awaited: until it lands the
    // helper reports 'Unknown', and a failing platform channel here must not
    // hold the app on its splash.
    unawaited(AppInfoHelper.initialize());

    // Connect route observer to RouteAwareWidget if provided
    if (routeObserver != null) {
      RouteAwareWidget.observer = routeObserver;
    }

    // Configure System Settings (Orientation & UI Overlay)
    await _configureSystemSettings();
  }

  static void _setupDynamicLogger() {
    DynamicLogger.configure(
      truncate: true,
      maxDepth: 20,
      maxCollectionEntries: 50,
    );
  }

  static void _setupHttpOverrides(
    AppProfile? profile,
    AppPlatform? platform,
    Flavor flavor,
  ) {
    // On the web the browser owns TLS: `dart:io`'s `HttpOverrides` compiles
    // there but nothing reads it — Dio uses the browser adapter, never an
    // `HttpClient` — so neither pinning nor the dev bypass can apply. Say so
    // once instead of installing an override that would suggest otherwise
    // (and instead of the "NOT pinned" ERROR below, which is about a
    // misconfiguration the web cannot fix).
    if (platform == AppPlatform.web) {
      DynamicLogger.log(
        'Web build: the browser validates TLS certificates. SSL pinning and '
        'the dev-flavor certificate bypass do not apply and are not '
        'installed.',
        tag: 'Security',
        level: LogLevel.INFO,
      );
      return;
    }

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

    // A platform whose pinning plugin has no implementation (desktop): there is
    // nothing to pin with, so say so once rather than log an ERROR about a
    // misconfiguration the app cannot fix — and never route every HTTPS call
    // through a client that cannot serve it.
    if (platform != null && !platform.canPinTls) {
      DynamicLogger.log(
        'SSL pinning is not applicable on ${platform.name}: the pinning '
        'plugin has no implementation here. TLS is validated by the platform.',
        tag: 'Security',
        level: LogLevel.INFO,
      );
      return;
    }

    // The app's declared decision for this flavor, when it declared itself.
    if (profile != null) {
      _applyDeclaredPinning(profile, flavor);
      return;
    }

    // Apply Global SSL Certificate Pinning via HttpSecurityPinningClient.
    // This automatically secures all HttpClients in the entire application
    // (including Dio, Image loaders, WebSockets, etc.)
    //
    // Requires `SslPinningConfig` to be registered in GetIt. Registering only
    // the `NetworkConfig` subtype is not enough — GetIt resolves by exact
    // type — which is why the app shell binds it explicitly in
    // `platform/shell/adapters/lib/di/network_binding_module.dart`.
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

  /// Pinning as the app's manifest decided it for the current flavor
  /// (`flavors.<f>.ssl_pinning`): pinned installs the pinning client with
  /// exactly those hashes, disabled logs the declared reason, and no decision
  /// at all — which `AppProfile.validate` already refuses (`P04`) — is an
  /// ERROR.
  static void _applyDeclaredPinning(AppProfile profile, Flavor flavor) {
    final decision = profile.facts.sslPinning.decisionFor(flavor);
    switch (decision) {
      case PinnedSsl(:final hashes):
        HttpOverrides.global = _MyHttpSecurityPinningHttpOverrides(hashes);
      case DisabledSsl(:final reason):
        DynamicLogger.log(
          'SSL pinning is disabled for flavor ${flavor.name}: $reason. '
          'Traffic is NOT pinned.',
          tag: 'Security',
          level: LogLevel.WARNING,
        );
      case null:
        DynamicLogger.log(
          'SSL pinning has no decision for flavor ${flavor.name} in '
          'apps/${profile.facts.id}/app_manifest.yaml '
          '(flavors.${flavor.name}.ssl_pinning). Traffic is NOT pinned.',
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
    final phoneSized = shortestSide < _phoneMaxShortestSide;
    return phoneSized ? const [DeviceOrientation.portraitUp] : const [];
  }

  /// The Material 3 `medium` breakpoint, in logical pixels — the same value
  /// as `core_responsive`'s `ResponsiveConstants.BREAKPOINT_MEDIUM`. Spelled
  /// out here because `core_common` is foundation and must not depend on the
  /// ui group; the lock is a fixed device question, not a configurable
  /// window-size-class boundary.
  static const double _phoneMaxShortestSide = 600;

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
