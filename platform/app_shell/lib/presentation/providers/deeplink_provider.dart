import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:core_common/core_common.dart';
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
/// way they got there — links are not routed over onboarding or login.
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
    DynamicLogger.log('Deep link: $uri', tag: 'DeepLink');
    final isWebLink = uri.scheme == 'http' || uri.scheme == 'https';
    // A custom-scheme link carries its first segment in the host position.
    final path = isWebLink ? uri.path : '/${uri.host}${uri.path}';
    final location = Uri(
      path: path.isEmpty ? '/' : path,
      queryParameters: uri.queryParameters.isEmpty ? null : uri.queryParameters,
    ).toString();
    _router.go(location);
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }
}
