import 'dart:async';

import 'package:core_common/core_common.dart';
import 'package:flutter/material.dart';
import 'package:injectable/injectable.dart';

/// Global application state provider for managing app-wide functionality
@lazySingleton
class AppProvider extends ChangeNotifier with LifecycleMixin, NetworkMixin {
  AppProvider() {
    // Initialize lifecycle monitoring for app state changes
    startListenOnLifecycleChange();

    // Initialize network connectivity monitoring
    startListenOnNetworkConnect();
  }

  StreamSubscription? _notificationDataSubscription;
  StreamSubscription? _onDeviceTokenChange;
  StreamSubscription? _userTokenChange;
  StreamSubscription? _chatNotifySubscription;

  @override
  void dispose() {
    stopListenOnLifecycleChange();
    stopListenOnNetworkConnect();
    _notificationDataSubscription?.cancel();
    _onDeviceTokenChange?.cancel();
    _userTokenChange?.cancel();
    _chatNotifySubscription?.cancel();
    super.dispose();
  }

  @override
  void onShow() {
    startListenOnNetworkConnect();
  }

  @override
  void onHide() {
    stopListenOnNetworkConnect();
  }

  @override
  void onNetworkConnected() {}
}
