import 'package:core_common/core_common.dart';
import 'package:core_di/core_di.dart';
import 'package:core_storage/core_storage.dart';
import 'package:flutter/material.dart';
import 'package:injectable/injectable.dart';

@Singleton(as: ILanguageStorage)
class LanguageStorageImpl implements ILanguageStorage {
  final StorageValuePresets _storagePresets;

  LanguageStorageImpl(this._storagePresets);

  @override
  Locale getLanguage() {
    final localString = _storagePresets.locale.value;
    if (localString == null) return AppConfig.defaultLanguage;
    return Locale(localString);
  }

  @override
  void saveLanguage(Locale mode) {
    _storagePresets.locale.save(mode.languageCode);
  }
}
