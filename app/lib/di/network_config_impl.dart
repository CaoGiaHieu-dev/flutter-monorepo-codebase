import 'package:core_common/core_common.dart';
import 'package:core_network/core_network.dart';
import 'package:core_storage/core_storage.dart';
import 'package:feature_shared/feature_shared.dart';
import 'package:flutter/material.dart';
import 'package:injectable/injectable.dart';

import '../presentation/navigation/app_router.dart';

/// Concrete implementation of NetworkConfig for the main application shell.
///
/// This fulfills dependencies of core_network using core_storage for credentials
/// and core_base_ui for retry overlay dialogs, without creating circular
/// package dependencies.
///
/// All storage access goes through the DI-injected [StorageValuePresets]
/// instance — no static calls.
@Singleton(as: NetworkConfig)
class NetworkConfigImpl implements NetworkConfig {
  final StorageValuePresets _storagePresets;

  /// Constructor – receives [StorageValuePresets] and [AppRouter] through DI.
  NetworkConfigImpl(this._storagePresets);

  @override
  String? Function() get getToken =>
      () => _storagePresets.token.value;

  @override
  String? Function() get getLocale =>
      () => _storagePresets.locale.value;

  @override
  void onRetryCallback({
    required VoidCallback onRetry,
    required VoidCallback onCancel,
  }) {
    AppDialogController.show(
      builder: (context) {
        return RetryDialog(
          onRetry: () {
            AppOverlay.removeDialogOverlay();
            onRetry();
          },
          onCancel: () {
            AppOverlay.removeDialogOverlay();
            onCancel();
          },
        );
      },
    );
  }

  @override
  List<String> get sslPinningHashes => const [];
}
