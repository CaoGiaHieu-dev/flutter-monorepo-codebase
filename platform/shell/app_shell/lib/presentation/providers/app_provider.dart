import 'package:core_common/core_common.dart';
import 'package:injectable/injectable.dart';
import 'package:material_ui/material_ui.dart';

/// Global application state provider for managing app-wide functionality
@lazySingleton
class AppProvider extends ChangeNotifier
    with LifecycleMixin, NetworkMixin, DisposeGuard {
  AppProvider() {
    // Initialize lifecycle monitoring for app state changes
    startListenOnLifecycleChange();

    // Initialize network connectivity monitoring
    startListenOnNetworkConnect();
  }

  @override
  void dispose() {
    stopListenOnLifecycleChange();
    stopListenOnNetworkConnect();
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
