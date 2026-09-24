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
/// `UndefineRouteWidget`, like any unknown location, so this class names no
/// feature route and stays removable-safe.
///
/// Started by `NavigatorWrapperWidget` once the user reaches home, whichever
/// way they got there — links are not routed over onboarding or login. In a
/// build with no auth module, where no sign-in ever leads home, it starts
/// instead when the user first leaves the entry location (onboarding).
///
/// The subscription outlives a sign-out, so every link is also checked
/// against the session when it **arrives**: while an auth module reports
/// nobody signed in, the link is dropped rather than opening a signed-in
/// screen over the login page. The session is read through
/// [IAuthSessionState] with `getItOrNull`; a build composing no auth module
/// has no session to guard, and routes every link.
@lazySingleton
class DeeplinkProvider extends ChangeNotifier with DisposeGuard {
  DeeplinkProvider(this._router);

  final AppRouter _router;
  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSubscription;

  /// Starts listening. Idempotent: a second call would otherwise add a second
  /// listener and route every link twice.
  void initAppLink() {
    _linkSubscription ??= _appLinks.uriLinkStream.listen(_handleDeepLink);
  }

  void _handleDeepLink(Uri uri) {
    if (!canRoute(getItOrNull<IAuthSessionState>())) {
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

  /// Whether a link may be routed now: always without an auth module
  /// ([session] null), otherwise only while someone is signed in.
  static bool canRoute(IAuthSessionState? session) =>
      session == null || session.signedInUser != null;

  /// The router location an app link points at.
  static String locationOf(Uri uri) {
    final isWebLink = uri.scheme == 'http' || uri.scheme == 'https';
    // A custom-scheme link carries its first segment in the host position.
    final path = isWebLink ? uri.path : '/${uri.host}${uri.path}';
    return Uri(
      path: path.isEmpty ? '/' : path,
      queryParameters: uri.queryParameters.isEmpty ? null : uri.queryParameters,
    ).toString();
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }
}
