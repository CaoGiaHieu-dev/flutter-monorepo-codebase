import 'package:domain_core/domain_core.dart';

abstract class ILanguageRepository {
  Result<void> setLanguage(String languageCode);
  Result<String> getLanguage();
}
