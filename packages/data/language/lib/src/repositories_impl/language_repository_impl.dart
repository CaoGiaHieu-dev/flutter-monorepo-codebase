import 'package:core_common/core_common.dart';
import 'package:core_storage/core_storage.dart';
import 'package:data_core/data_core.dart';
import 'package:domain_core/domain_core.dart';
import 'package:domain_language/domain_language.dart';
import 'package:injectable/injectable.dart';

import '../utils/language_storage_keys.dart';

/// NOTE: `app/lib/di/language_storage_impl.dart` (app-shell) independently
/// declares its own [StorageValue] for the same physical key `'locale'`.
/// This is intentional — this repository is sample/reference code for the
/// domain_language use-case path, not yet wired to the live Settings UI
/// (Settings currently uses `LanguageProvider`, which bypasses Domain per
/// AGENTS.md §2). The two instances are not required to stay in sync.
@LazySingleton(as: ILanguageRepository)
class LanguageRepositoryImpl extends IBaseRepository
    implements ILanguageRepository {
  LanguageRepositoryImpl(this._storageManager);

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
  Result<String> getLanguage() {
    return executeSync<String, String>(() {
      final language = _locale.value;
      if (language != null) return language;
      return AppConfig.defaultLanguage.languageCode;
    });
  }

  @override
  Result<void> setLanguage(String languageCode) {
    return executeSync<void, void>(() {
      _locale.value = languageCode;
    });
  }
}
