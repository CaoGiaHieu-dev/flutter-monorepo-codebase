import 'package:core_database/core_database.dart';
import 'package:injectable/injectable.dart';

/// Contract for reading/writing cache rows via Drift.
abstract class ICacheEntryLocalDataSource {
  Future<void> save(String key, String value);

  Future<String?> get(String key);

  Future<CacheEntry?> getEntry(String key);

  Future<void> delete(String key);

  Future<List<CacheEntry>> getAll();
}

/// Example local data source — demonstrates how the Data layer consumes
/// [AppDatabase] from `core_database` without exposing Drift to Domain.
@LazySingleton(as: ICacheEntryLocalDataSource)
class CacheEntryLocalDataSource implements ICacheEntryLocalDataSource {
  CacheEntryLocalDataSource(this._database);

  final AppDatabase _database;

  @override
  Future<void> save(String key, String value) {
    return _database.cacheEntriesDao.upsert(key, value);
  }

  @override
  Future<String?> get(String key) {
    return _database.cacheEntriesDao.getValue(key);
  }

  @override
  Future<CacheEntry?> getEntry(String key) {
    return _database.cacheEntriesDao.getEntry(key);
  }

  @override
  Future<void> delete(String key) {
    return _database.cacheEntriesDao.deleteByKey(key);
  }

  @override
  Future<List<CacheEntry>> getAll() {
    return _database.cacheEntriesDao.getAll();
  }
}
