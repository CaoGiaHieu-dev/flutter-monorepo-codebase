/// Physical storage keys owned exclusively by `feature_language`'s data
/// layer sample (`LanguageRepositoryImpl`).
///
/// Package-internal by convention — mirrors the same pattern used by
/// `AuthStorageKeys` in `data_auth`.
class LanguageStorageKeys {
  LanguageStorageKeys._();

  static const String LOCALE = 'locale';
}
