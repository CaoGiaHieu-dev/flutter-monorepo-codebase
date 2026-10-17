part of '../cache_database.dart';

/// Data access object for [CacheEntries].
@DriftAccessor(tables: [CacheEntries])
class CacheEntriesDao extends DatabaseAccessor<CacheDatabase>
    with _$CacheEntriesDaoMixin {
  CacheEntriesDao(super.attachedDatabase);

  /// Inserts or replaces a cache row.
  Future<void> upsert(String key, String value) {
    return into(cacheEntries).insertOnConflictUpdate(
      CacheEntriesCompanion.insert(
        key: key,
        value: value,
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Reads the row for [key], or `null` when missing.
  Future<CacheEntry?> getEntry(String key) {
    return (select(
      cacheEntries,
    )..where((t) => t.key.equals(key))).getSingleOrNull();
  }
}
