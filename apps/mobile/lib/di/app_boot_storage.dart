import 'package:core_storage/core_storage.dart';
import 'package:injectable/injectable.dart';

import 'utils/app_boot_storage_keys.dart';

/// Owns app-shell-level boot flags (e.g. onboarding-viewed) that don't
/// belong to any single feature/domain. Not exposed outside app/lib.
@singleton
class AppBootStorage {
  AppBootStorage(this._storageManager);
  final StorageManager _storageManager;

  late final viewedOnboard = StorageValue<bool>(
    _storageManager.getStorage(StorageType.pref),
    AppBootStorageKeys.VIEWED_ONBOARD,
    reviver: (key, value) {
      if (value == null) return false;
      return bool.tryParse(value.toString()) ?? false;
    },
  );

  @PostConstruct(preResolve: true)
  Future<void> initialize() async {
    await viewedOnboard.readFromStorage();
  }
}
