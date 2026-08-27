import 'package:core_common/core_common.dart';
import 'package:core_di/core_di.dart';
import 'package:core_storage/core_storage.dart';
import 'package:flutter/material.dart';
import 'package:injectable/injectable.dart';

import 'utils/language_storage_keys.dart';

@Singleton(as: ILanguageStorage)
class LanguageStorageImpl implements ILanguageStorage {
  LanguageStorageImpl(this._storageManager);
  final StorageManager _storageManager;

  late final _locale = StorageValue<String>(
    _storageManager.getStorage(StorageType.pref),
    LanguageStorageKeys.LOCALE,
  );

  @PostConstruct(preResolve: true)
  Future<void> initialize() async {
    await _locale.readFromStorage();
  }

  @override
  Locale getLanguage() {
    final localString = _locale.value;
    if (localString == null) return AppConfig.defaultLanguage;
    return Locale(localString);
  }

  @override
  void saveLanguage(Locale mode) {
    _locale.save(mode.languageCode);
  }
}
