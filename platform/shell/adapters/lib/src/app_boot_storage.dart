import 'package:core_storage/core_storage.dart';
import 'package:injectable/injectable.dart';

import 'utils/app_boot_storage_keys.dart';

/// Owns app-shell-level boot flags (e.g. onboarding-viewed) that don't
/// belong to any single feature/domain.
///
/// Read by `platform_app_shell` (`AppRouter`'s first-launch location and
/// `NavigatorWrapperWidget`) — no module reads it. The [StorageValue] stays
/// private (RULE-44): callers read [viewedOnboard] and write through
/// [markOnboardViewed].
@singleton
class AppBootStorage {
  AppBootStorage(this._storageManager);
  final StorageManager _storageManager;

  late final _viewedOnboard = StorageValue<bool>(
    _storageManager.getStorage(StorageType.pref),
    AppBootStorageKeys.VIEWED_ONBOARD,
    reviver: (key, value) {
      if (value == null) return false;
      return bool.tryParse(value.toString()) ?? false;
    },
  );

  @PostConstruct(preResolve: true)
  Future<void> initialize() async {
    await _viewedOnboard.readFromStorage();
  }

  /// Whether the first-launch entry location (onboarding) has been shown.
  bool get viewedOnboard => _viewedOnboard.value ?? false;

  /// Records that the entry location has been shown. The in-memory value
  /// changes at once; the returned future completes when it is persisted.
  Future<void> markOnboardViewed() => _viewedOnboard.save(true);
}
