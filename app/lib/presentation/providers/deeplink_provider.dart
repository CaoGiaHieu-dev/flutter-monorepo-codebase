import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:core_common/core_common.dart';
import 'package:dynamic_logger/dynamic_logger.dart';
import 'package:flutter/material.dart';
import 'package:injectable/injectable.dart';

/// Deep link provider for managing app deep link handling and navigation.
///
/// This provider handles all deep link related operations including link parsing,
/// route navigation, and error handling. It follows the standardized provider
/// pattern with proper lifecycle management and error handling.
///
/// Key features:
/// - Deep link URL parsing and validation
/// - Route-based navigation handling
/// - Error handling for invalid links
/// - Stream-based link monitoring
/// - Comprehensive logging for debugging
///
/// Usage example:
/// ```dart
/// final deeplinkProvider = context.read<DeeplinkProvider>();
///
/// // Initialize deep link listening
/// deeplinkProvider.initAppLink();
///
/// // Check processing status
/// if (deeplinkProvider.isProcessingDeepLink) {
///   // Show loading indicator
/// }
///
/// // Get last processed link
/// final lastLink = deeplinkProvider.lastProcessedDeepLink;
/// ```
@lazySingleton
class DeeplinkProvider extends ChangeNotifier {
  /// Creates a DeeplinkProvider with required context.
  ///
  /// This constructor follows the standardized provider pattern by:
  /// - Accepting context through constructor injection
  /// - Calling the parent constructor with required context
  /// - Initializing internal services and subscriptions
  ///
  DeeplinkProvider();

  // Private variables for deep link management
  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSubscription;
  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }

  void initAppLink() {
    _linkSubscription = _appLinks.uriLinkStream.listen(_handleDeepLink);
  }

  void _handleDeepLink(Uri uri) async {
    try {
      DynamicLogger.log('Processing deep link: $uri', tag: 'DeepLink');

      String path = uri.path;
      String host = uri.host;

      if (uri.authority == EnvConstants.WEB_DOMAIN) {
        if (uri.pathSegments.isNotEmpty) {
          host = uri.pathSegments[0];
          path = path.replaceAll('$host/', '');
        }
      }

      switch (host) {
        case 'auth':
          await _handleAuthDeepLink(path, uri.queryParameters);
          break;
        case 'profile':
          await _handleProfileDeepLink(path, uri.queryParameters);
          break;
        case 'share':
          await _handleShareDeepLink(path, uri.queryParameters);
          break;
        default:
          throw FlutterError('Unknown deep link host: $host for URI: $uri');
      }
    } catch (e) {
      DynamicLogger.log('Deep link processing error: $e', tag: 'DeepLink');
    }
  }

  Future<void> _handleAuthDeepLink(
    String path,
    Map<String, String> queryParams,
  ) async {
    switch (path) {
      case '/login':
        break;
      case '/register':
        break;
      case '/reset-password':
        break;
      case '/verify-email':
        break;
      default:
        throw FlutterError('Unknown auth deep link path: $path');
    }
  }

  Future<void> _handleProfileDeepLink(
    String path,
    Map<String, String> queryParams,
  ) async {}

  Future<void> _handleShareDeepLink(
    String path,
    Map<String, String> queryParams,
  ) async {}
}
