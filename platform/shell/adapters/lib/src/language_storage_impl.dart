import 'package:core_common/core_common.dart';
import 'package:core_di/core_di.dart';
import 'package:core_storage/core_storage.dart';
import 'package:injectable/injectable.dart';
import 'package:material_ui/material_ui.dart';

import 'utils/language_storage_keys.dart';

@Singleton(as: ILanguageStorage)
class LanguageStorageImpl implements ILanguageStorage {
  /// [profile] is the app's `LocaleProfile`: its `initial` language is what a
  /// first launch opens in, before the user picks one.
  LanguageStorageImpl(
    this._storageManager, [
    this._profile = const LocaleProfile(),
  ]);
  final StorageManager _storageManager;
  final LocaleProfile _profile;

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
    if (localString != null) return Locale(localString);
    // Nothing chosen yet: the app's initial language, else the device's.
    final initial = _profile.initial;
    return initial == null ? AppConfig.defaultLanguage : Locale(initial);
  }

  @override
  void saveLanguage(Locale mode) {
    _locale.save(mode.languageCode);
  }
}
