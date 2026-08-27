import 'package:core_di/core_di.dart';
import 'package:core_storage/core_storage.dart';
import 'package:flutter/material.dart';
import 'package:injectable/injectable.dart';

import 'utils/theme_storage_keys.dart';

@Singleton(as: IThemeStorage)
class ThemeStorageImpl implements IThemeStorage {
  ThemeStorageImpl(this._storageManager);
  final StorageManager _storageManager;

  late final _themeMode = StorageValue<ThemeMode>(
    _storageManager.getStorage(StorageType.pref),
    ThemeStorageKeys.THEME_MODE,
    reviver: (key, value) {
      if (value == null) return ThemeMode.system;
      return ThemeMode.values.byName(value.toString());
    },
  );

  @PostConstruct(preResolve: true)
  Future<void> initialize() async {
    await _themeMode.readFromStorage();
  }

  @override
  ThemeMode getThemeMode() {
    return _themeMode.value ?? ThemeMode.system;
  }

  @override
  void saveThemeMode(ThemeMode mode) {
    _themeMode.save(mode);
  }
}
