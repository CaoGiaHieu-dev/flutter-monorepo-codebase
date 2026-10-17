/// Constants owned exclusively by `data_cache`.
class CacheConstants {
  CacheConstants._();

  /// SQLite file of this package's [CacheDatabase], named after its owner:
  /// each package that persists data opens its own file.
  static const String DATABASE_FILE_NAME = 'cache.sqlite';
}
