/// Constants owned exclusively by `data_core`.
///
/// Package-internal by convention: nothing outside this package should name
/// these values. Other packages own their own `utils/` folder.
class DataCoreConstants {
  DataCoreConstants._();

  /// On-disk SQLite file for this package's [CacheDatabase], resolved inside
  /// the app documents directory.
  ///
  /// Named after its owner rather than the app, because each package that
  /// persists data opens its own file. Changing this value points the package
  /// at a different database and makes existing on-device rows unreachable.
  static const String CACHE_DATABASE_FILE_NAME = 'data_core_cache.sqlite';
}
