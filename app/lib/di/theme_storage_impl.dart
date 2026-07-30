import 'package:core_di/core_di.dart';
import 'package:core_storage/core_storage.dart';
import 'package:flutter/material.dart';
import 'package:injectable/injectable.dart';

@Singleton(as: IThemeStorage)
class ThemeStorageImpl implements IThemeStorage {
  ThemeStorageImpl(this._storagePresets);
  final StorageValuePresets _storagePresets;

  @override
  ThemeMode getThemeMode() {
    return _storagePresets.themeMode.value ?? ThemeMode.system;
  }

  @override
  void saveThemeMode(ThemeMode mode) {
    _storagePresets.themeMode.save(mode);
  }
}
