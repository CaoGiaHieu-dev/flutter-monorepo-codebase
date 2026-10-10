import 'dart:async';
import 'dart:io';

import 'package:dynamic_logger/dynamic_logger.dart';
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
  /// `runShellApp` calls this **before** dependency injection starts, so
  /// nothing the graph builds — an eager singleton, a contract implementation
  /// the composition check instantiates, a controller on the splash — can open
  /// a connection ahead of it. It cannot wait for [init]: Dio's
  /// `IOHttpClientAdapter` keeps the `HttpClient` it created first, so a
  /// connection opened before the override is installed (unpinned) would serve
  /// the whole session. It needs no registration: it reads only the app's
  /// [profile].
  ///
  /// Certificate pinning follows the app's declared decision for the [flavor]
  /// this run is built as (`AppConfig.appFlavor`): `flavors.<f>.
  /// ssl_pinning` in the manifest, carried by [AppFacts.sslPinning]
  /// ([SslPinningPolicy]). Pinned installs the pinning client with exactly
  /// those hashes — a hash the client cannot parse throws an
  /// [InvalidPinException] here, so the boot stops with the pin named
  /// instead of the first request failing as a "network" error — disabled
  /// logs its reason, and the web, the one platform that cannot pin TLS
  /// (`AppPlatform.canPinTls`: the browser owns TLS), says so once instead
  /// of installing or complaining. [platform] is the platform this run is on
  /// (`resolveAppPlatform()`, the one place that reads the runtime): the
  /// caller says where it runs, this class never guesses.
  ///
  /// Idempotent: [init] calls it too, for a host that never called it, and a
  /// second call installs nothing.
  static void initBeforeRunApp({
    required AppProfile profile,
    required AppPlatform platform,
    required Flavor flavor,
  }) {
    if (_ranBeforeRunApp) return;

    // Configure Dynamic Logger
    _setupDynamicLogger();

    // Certificate handling: pinning, or — debug + explicit dev flavor only —
    // a bypass for local self-signed servers. Recorded as done only after it
    // returned: a pin the client cannot parse throws from here, and the
    // boot-failure screen's retry must throw again, not find the flag set
    // and start the app with no pinning.
    _setupHttpOverrides(profile, platform, flavor);
    _ranBeforeRunApp = true;
  }

  /// Lets a test run [initBeforeRunApp] again.
  @visibleForTesting
  static void debugResetBeforeRunApp() => _ranBeforeRunApp = false;

  /// The pinning `HttpOverrides` for [pins], built but not installed, so a
  /// test can feed it a list no `SslPinning.pinned` decision can produce
  /// (that type always carries a leaf and a backup).
  @visibleForTesting
  static HttpOverrides debugPinningOverrides(List<String> pins) =>
      _MyHttpSecurityPinningHttpOverrides(pins);

  /// Performs all required startup initializations.
  static Future<void> init({
    required AppProfile profile,
    required AppPlatform platform,
    required Flavor flavor,
    RouteObserver<ModalRoute<void>>? routeObserver,
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
    await _configureSystemSettings(profile, platform);
  }

  static void _setupDynamicLogger() {
    DynamicLogger.configure(
      truncate: true,
      maxDepth: 20,
      maxCollectionEntries: 50,
    );
  }

  static void _setupHttpOverrides(
    AppProfile profile,
    AppPlatform platform,
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
    // treated as `prod` here. A fallback to `dev` would let a build without
    // `--flavor` — release included — accept any certificate.
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
        '--flavor dev to allow self-signed certificates in a debug build '
        '(on the web: --dart-define=APP_FLAVOR=dev).',
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

    // The app's declared decision for this flavor (`flavors.<f>.ssl_pinning`).
    // Installing the pinning client secures every `HttpClient` in the
    // application (Dio, image loaders, web sockets).
    _applyDeclaredPinning(profile, flavor);
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

  static Future<void> _configureSystemSettings(
    AppProfile profile,
    AppPlatform platform,
  ) async {
    // An undeclared platform (`P01`, only reachable with
    // ALLOW_UNDECLARED_PLATFORM) runs on the template defaults, as the boot
    // does everywhere else.
    final facts =
        profile.facts.platformFor(platform) ?? const PlatformFacts.today();
    await SystemChrome.setPreferredOrientations(
      preferredOrientationsFor(
        _shortestSideAtLaunch(),
        policy: facts.orientation,
        phoneMaxShortestSide: profile.display.phoneMaxShortestSide,
      ),
    );
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
  }

  /// The orientations to allow on a display whose shortest side is
  /// [shortestSide] logical pixels (`null` when it could not be measured),
  /// under the platform's declared [policy]
  /// (`platforms.<p>.orientation` in the app manifest).
  ///
  /// - [OrientationPolicy.phonesPortrait], the default: a phone-sized display
  ///   (shortest side below [phoneMaxShortestSide] — the app's
  ///   `DisplayProfile.phoneMaxShortestSide`, 600 by default, the Material 3
  ///   `medium` breakpoint) is locked to portrait: the phone layouts are
  ///   designed for it. Anything larger — a tablet, an unfolded foldable, a
  ///   desktop — gets every orientation (an empty list means "no
  ///   preference"), so it is never letterboxed and its landscape and rail
  ///   layouts are reachable. An unmeasurable display is left unlocked too,
  ///   rather than guessed to be a phone.
  /// - [OrientationPolicy.free]: never locked.
  /// - [OrientationPolicy.portrait]: always portrait.
  /// - [OrientationPolicy.landscape]: always landscape.
  ///
  /// This is a device question — whether to lock at all — so it is decided
  /// once from the display at launch. Layout still follows the window size
  /// class, never this.
  static List<DeviceOrientation> preferredOrientationsFor(
    double? shortestSide, {
    OrientationPolicy policy = OrientationPolicy.phonesPortrait,
    double? phoneMaxShortestSide,
  }) {
    switch (policy) {
      case OrientationPolicy.free:
        return const [];
      case OrientationPolicy.portrait:
        return const [DeviceOrientation.portraitUp];
      case OrientationPolicy.landscape:
        return const [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ];
      case OrientationPolicy.phonesPortrait:
        if (shortestSide == null) return const [];
        final threshold =
            phoneMaxShortestSide ?? const DisplayProfile().phoneMaxShortestSide;
        return shortestSide < threshold
            ? const [DeviceOrientation.portraitUp]
            : const [];
    }
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
  _MyHttpSecurityPinningHttpOverrides(this.pins) {
    // The package reads an empty pin list as "this host is not pinned" (system
    // trust, no probe), so an empty list would install a client that pins
    // nothing. A pinned decision always carries a leaf and a backup; refuse
    // anything else here, where a release build (asserts off) still checks.
    if (pins.isEmpty) {
      throw ArgumentError.value(
        pins,
        'pins',
        'a pinned decision needs at least one pin',
      );
    }
    // The client parses its pins when it is built, i.e. at the first
    // `HttpClient()` of the process, where a bad pin would surface as a
    // failed request. Parse them here, at boot, so the pin is named and the
    // app never starts on a pin it cannot enforce.
    for (final pin in pins) {
      SpkiPin.parse(pin);
    }
  }

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    // The package builds the clients it wraps under no-op overrides, so
    // being the global `HttpOverrides` does not recurse.
    //
    // `Object` and a type test, not a typed local or a subclass: this file is
    // compiled for the web, where the package's class is an `http.BaseClient`
    // and not an `HttpClient`. A direct return or an override of `open`
    // fails `flutter build web` while `flutter analyze` stays clean. The web
    // never reaches this line (`AppPlatform.canPinTls` is false there); the
    // test only turns a bare `TypeError` into a message that names the cause.
    final Object client = HttpSecurityPinningClient(pins);
    if (client is! HttpClient) {
      throw UnsupportedError('SSL pinning is not available on the web');
    }
    return client;
  }
}
