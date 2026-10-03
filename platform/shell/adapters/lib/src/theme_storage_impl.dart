import 'package:core_common/core_common.dart';
import 'package:core_di/core_di.dart';
import 'package:core_storage/core_storage.dart';
import 'package:injectable/injectable.dart';
import 'package:material_ui/material_ui.dart';

import 'utils/theme_storage_keys.dart';

@Singleton(as: IThemeStorage)
class ThemeStorageImpl implements IThemeStorage {
  /// [profile] is the app's `ThemeProfile`: its `mode` is what a first launch
  /// opens in, before the user picks one.
  ThemeStorageImpl(
    this._storageManager, [
    ThemeProfile profile = const ThemeProfile(),
  ]) : _defaultMode = switch (profile.mode) {
         ThemeModeSetting.system => ThemeMode.system,
         ThemeModeSetting.light => ThemeMode.light,
         ThemeModeSetting.dark => ThemeMode.dark,
       };
  final StorageManager _storageManager;
  final ThemeMode _defaultMode;

  late final _themeMode = StorageValue<ThemeMode>(
    _storageManager.getStorage(StorageType.pref),
    ThemeStorageKeys.THEME_MODE,
    reviver: (key, value) {
      if (value == null) return _defaultMode;
      return ThemeMode.values.byName(value.toString());
    },
  );

  @PostConstruct(preResolve: true)
  Future<void> initialize() async {
    await _themeMode.readFromStorage();
  }

  @override
  ThemeMode getThemeMode() {
    return _themeMode.value ?? _defaultMode;
  }

  @override
  void saveThemeMode(ThemeMode mode) {
    _themeMode.save(mode);
  }
}
