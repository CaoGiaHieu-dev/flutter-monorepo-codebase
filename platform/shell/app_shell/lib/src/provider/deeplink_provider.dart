import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:core_common/core_common.dart';
import 'package:core_di/core_di.dart';
import 'package:dynamic_logger/dynamic_logger.dart';
import 'package:injectable/injectable.dart';
import 'package:material_ui/material_ui.dart';

import '../navigation/app_router.dart';

/// Turns incoming app links into router locations.
///
/// `https://<WEB_DOMAIN>/settings?tab=2` and `<scheme>://settings?tab=2` both
/// go to `/settings?tab=2`. A path no module registered lands on
/// `UndefinedRouteWidget`, like any unknown location, so this class names no
/// feature route and stays removable-safe.
///
/// Started by `NavigatorWrapperWidget` once the user reaches the post-sign-in
/// location, whichever way they got there — links are not routed over
/// onboarding or the sign-in screen. In a build with no session owner, where
/// no sign-in ever happens, it starts instead when the user first leaves the
/// entry location (onboarding).
///
/// The subscription outlives a sign-out, so every link is also checked
/// against the session when it **arrives**: while the session owner reports
/// nobody signed in, the link is dropped rather than opening a signed-in
/// screen over the sign-in page. The session is read through
/// [ISessionState] with `getItOrNull`; a build composing no session owner
/// has no session to guard, and routes every link.
///
/// An app can switch deep links off for a platform
/// (`platforms.<p>.deep_links: false` in its manifest, handed over as
/// [PlatformFacts.deepLinks]): [initAppLink] then logs one INFO line naming
/// the key and subscribes to nothing.
@lazySingleton
class DeeplinkProvider extends ChangeNotifier with DisposeGuard {
  /// [_platform] is what the app declared for the platform it runs on
  /// (`registerAppProfile` registers it before DI). The `const` default — the
  /// template's, deep links on — serves a provider built by hand; a graph
  /// resolves the registered section.
  DeeplinkProvider(
    this._router, [
    this._platform = const PlatformFacts.today(),
  ]);

  final AppRouter _router;
  final PlatformFacts _platform;
  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSubscription;
  bool _loggedOff = false;

  /// Starts listening. Idempotent: a second call would otherwise add a second
  /// listener and route every link twice.
  ///
  /// With deep links switched off for this platform it logs once and returns,
  /// however often it is called: the `app_links` stream is never touched.
  void initAppLink() {
    if (!_platform.deepLinks) {
      if (!_loggedOff) {
        _loggedOff = true;
        DynamicLogger.log(
          'Deep links are off: ${platformSwitchKey('deep_links')} is false, '
          'so incoming links are not listened to.',
          tag: 'DeepLink',
          level: LogLevel.INFO,
        );
      }
      return;
    }
    _linkSubscription ??= _appLinks.uriLinkStream.listen(_handleDeepLink);
  }

  void _handleDeepLink(Uri uri) {
    if (!canRoute(getItOrNull<ISessionState>())) {
      DynamicLogger.log(
        'Deep link ignored while signed out: $uri',
        tag: 'DeepLink',
        level: LogLevel.WARNING,
      );
      return;
    }
    DynamicLogger.log('Deep link: $uri', tag: 'DeepLink');
    _router.go(locationOf(uri));
  }

  /// Whether a link may be routed now: always without a session owner
  /// ([session] null), otherwise only while someone is signed in.
  static bool canRoute(ISessionState? session) =>
      session == null || session.signedInUser != null;

  /// The router location an app link points at: its path, every query
  /// parameter (a key given twice keeps both values) and its fragment.
  ///
  /// A custom-scheme link carries its first path segment in the host position
  /// (`myapp://settings/detail` is `/settings/detail`); with an empty host
  /// (`myapp:///settings`) the path is already complete.
  static String locationOf(Uri uri) {
    final isWebLink = uri.scheme == 'http' || uri.scheme == 'https';
    final path = isWebLink || uri.host.isEmpty
        ? uri.path
        : '/${uri.host}${uri.path}';
    return Uri(
      path: path.isEmpty ? '/' : path,
      queryParameters: uri.hasQuery && uri.queryParametersAll.isNotEmpty
          ? uri.queryParametersAll
          : null,
      fragment: uri.hasFragment && uri.fragment.isNotEmpty
          ? uri.fragment
          : null,
    ).toString();
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }
}
