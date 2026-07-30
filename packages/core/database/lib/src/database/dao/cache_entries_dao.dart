part of '../app_database.dart';

/// Data access object for [CacheEntries].
@DriftAccessor(tables: [CacheEntries])
class CacheEntriesDao extends DatabaseAccessor<AppDatabase>
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

  /// Reads the payload for [key], or `null` when missing.
  Future<String?> getValue(String key) async {
    final row = await getEntry(key);
    return row?.value;
  }

  /// Reads the full row for [key], or `null` when missing.
  Future<CacheEntry?> getEntry(String key) {
    return (select(
      cacheEntries,
    )..where((t) => t.key.equals(key))).getSingleOrNull();
  }

  /// Deletes a single cache row.
  Future<int> deleteByKey(String key) {
    return (delete(cacheEntries)..where((t) => t.key.equals(key))).go();
  }

  /// Returns all cache rows ordered by most recently updated.
  Future<List<CacheEntry>> getAll() {
    return (select(
      cacheEntries,
    )..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])).get();
  }

  /// Clears the entire cache table.
  Future<int> clearAll() => delete(cacheEntries).go();
}
