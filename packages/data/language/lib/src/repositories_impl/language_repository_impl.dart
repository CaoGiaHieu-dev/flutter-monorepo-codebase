import 'package:core_common/core_common.dart';
import 'package:core_storage/core_storage.dart';
import 'package:data_core/data_core.dart';
import 'package:domain_core/domain_core.dart';
import 'package:domain_language/domain_language.dart';
import 'package:injectable/injectable.dart';

@LazySingleton(as: ILanguageRepository)
class LanguageRepositoryImpl extends IBaseRepository
    implements ILanguageRepository {
  LanguageRepositoryImpl(this._storage);

  final StorageValuePresets _storage;

  @override
  Result<String> getLanguage() {
    return executeSync<String, String>(() {
      final language = _storage.locale.value;
      if (language != null) {
        return language;
      }
      return AppConfig.defaultLanguage.languageCode;
    });
  }

  @override
  Result<void> setLanguage(String languageCode) {
    return executeSync<void, void>(() {
      _storage.locale.value = languageCode;
    });
  }
}
