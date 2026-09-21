import 'dart:async';

import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';
import 'package:material_ui/material_ui.dart';

import '../utils/app_utils.dart';

/// Mixin to handle network connectivity events.
///
/// This mixin provides methods to listen for network connection changes,
/// and handles the `onNetworkConnected` and `onNetworkDisconnected` events.
///
/// To use this mixin, simply extend your widget with this mixin and override the
/// `onNetworkConnected` and `onNetworkDisconnected` methods to handle the
/// respective events.
mixin NetworkMixin {
  /// A subscription to listen for network connectivity changes.
  StreamSubscription<InternetStatus>? _internetConnectionSubscription;

  /// Starts listening for network connection changes.
  ///
  /// This method subscribes to the `onStatusChange` stream of the
  /// [InternetConnectionChecker] and calls the `onNetworkConnected` and
  /// `onNetworkDisconnected` methods based on the connection status.
  ///
  /// This method should be called in the `initState` method of the widget.
  /// Call [stopListenOnNetworkConnect] in the `dispose` method.
  @mustCallSuper
  Future<void> startListenOnNetworkConnect() async {
    await stopListenOnNetworkConnect();
    _internetConnectionSubscription = AppUtils.internetConnection.onStatusChange
        .listen((event) {
          switch (event) {
            case InternetStatus.connected:
              onNetworkConnected();
              break;
            case InternetStatus.disconnected:
              onNetworkDisconnected();
              break;
          }
        });
  }

  /// Stops listening for network connectivity changes.
  ///
  /// This method cancels the subscription to the `onStatusChange` stream of the
  /// [InternetConnectionChecker].
  ///
  /// This method should be called in the `dispose` method of the widget.
  @mustCallSuper
  Future<void> stopListenOnNetworkConnect() async {
    await _internetConnectionSubscription?.cancel();
    _internetConnectionSubscription = null;
  }

  /// Called when the network connection is established.
  ///
  /// This method can be overridden to handle network connection events.
  /// For example, you can show a message to the user indicating that the
  /// network connection is available.
  void onNetworkConnected() {}

  /// Called when the network connection is lost.
  ///
  /// This method can be overridden to handle network connection events.
  /// For example, you can show a message to the user indicating that the
  /// network connection is unavailable, or you can disable features that
  /// require a network connection.
  void onNetworkDisconnected() {}
}
