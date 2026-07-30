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

  @override
  List<String> get sslPinningHashes;
}
