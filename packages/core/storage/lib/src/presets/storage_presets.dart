import 'package:core_common/core_common.dart';
import 'package:flutter/material.dart';
import 'package:injectable/injectable.dart';

import '../contracts/storage_manager.dart';
import '../contracts/storage_type.dart';
import '../contracts/storage_value.dart';

/// Pre-defined [StorageValue] instances for commonly used app data.
///
/// Provides type-safe, reactive access to:
/// - Authentication tokens ([token], [refreshToken])
/// - User profile data ([authUser])
/// - Locale/language preference ([locale])
/// - Theme mode preference ([themeMode])
///
/// All values are backed by the [StorageManager] which resolves backends
/// dynamically using [StorageType].
///
/// Usage (always via DI — never call statically):
/// ```dart
/// @injectable
/// class MyService {
///   final StorageValuePresets _storage;
///   MyService(this._storage);
///
///   String? get token => _storage.token.value;
/// }
/// ```
@Singleton()
class StorageValuePresets {
  final StorageManager _storageManager;

  /// Constructor — receives the [StorageManager] via DI.
  StorageValuePresets(this._storageManager);

  /// Forces initialization of all late final properties to trigger their registration.
  @PostConstruct(preResolve: true)
  Future<void> initialize() async {
    final storages = [
      token,
      refreshToken,
      authUser,
      locale,
      themeMode,
      viewedOnboard,
    ];
    await Future.wait(storages.map((storage) => storage.readFromStorage()));
  }

  // ---------------------------------------------------------------------------
  // Auth (Stored in secure storage)
  // ---------------------------------------------------------------------------

  /// Authentication token for API requests.
  late final token = StorageValue<String>(
    _storageManager.getStorage(StorageType.secure),
    StorageKeyConstants.TOKEN,
  );

  /// Refresh token for silent re-authentication.
  late final refreshToken = StorageValue<String>(
    _storageManager.getStorage(StorageType.secure),
    StorageKeyConstants.REFRESH_TOKEN,
  );

  /// Full user profile data (serialized as `Map<String, dynamic>`).
  late final authUser = StorageValue<Map<String, dynamic>>(
    _storageManager.getStorage(StorageType.secure),
    StorageKeyConstants.AUTH_USER,
  );

  // ---------------------------------------------------------------------------
  // Preferences (Stored in pref storage)
  // ---------------------------------------------------------------------------

  /// User's preferred locale (e.g. `"vi"`, `"en"`).
  late final locale = StorageValue<String>(
    _storageManager.getStorage(StorageType.pref),
    StorageKeyConstants.LOCALE,
  );

  /// User's preferred theme mode (light / dark / system).
  late final themeMode = StorageValue<ThemeMode>(
    _storageManager.getStorage(StorageType.pref),
    StorageKeyConstants.THEME_MODE,
    reviver: (key, value) {
      if (value == null) return ThemeMode.system;
      return ThemeMode.values.byName(value.toString());
    },
  );

  /// Flag indicating whether the user has viewed the onboarding screen.
  late final viewedOnboard = StorageValue<bool>(
    _storageManager.getStorage(StorageType.pref),
    StorageKeyConstants.VIEWED_ONBOARD,
    reviver: (key, value) {
      if (value == null) return false;
      return bool.tryParse(value.toString()) ?? false;
    },
  );
}
