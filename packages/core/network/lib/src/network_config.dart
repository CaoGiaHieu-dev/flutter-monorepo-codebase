import 'package:core_common/core_common.dart';
import 'package:flutter/foundation.dart';

/// Configuration interface for network services.
/// This allows the core_network package to remain fully decoupled from
/// specific storage mechanisms and visual/UI libraries while still performing
/// authorization injections and displaying UI components like retry dialogs.
abstract class NetworkConfig implements SslPinningConfig {
  /// Callback to get the current authentication token.
  String? Function() get getToken;

  /// Callback to get the current locale/language code.
  String? Function() get getLocale;

  /// Callback to display the retry confirmation dialog to the user.
  void onRetryCallback({
    required VoidCallback onRetry,
    required VoidCallback onCancel,
  });

  /// Refreshes the expired session and returns the new bearer token, or `null`
  /// when the refresh fails.
  ///
  /// Return `null` from this getter to disable automatic refresh entirely — in
  /// that case a `401` is surfaced to the caller unchanged, which is the
  /// behaviour of a client that has no refresh endpoint.
  ///
  /// Implementations must not issue the refresh call through an authenticated
  /// client; see [RefreshTokenInterceptor] for the recursion guard.
  Future<String?> Function()? get onRefreshToken => null;

  /// Invoked once when [onRefreshToken] could not produce a new token, so the
  /// app can clear the session and send the user back to the login screen.
  Future<void> Function()? get onRefreshFailed => null;

  @override
  List<String> get sslPinningHashes;
}
