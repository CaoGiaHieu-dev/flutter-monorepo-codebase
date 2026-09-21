// SAMPLE CODE — safe to delete.
//
// Part of the `cache_chain` sample: one complete vertical slice (table -> DAO
// -> data source -> repository -> entity -> use cases) kept as a copy-me
// template for your first real table.
//
// Nothing in the app consumes it. `unused_checker` will not flag it because it
// is registered in DI, and the tests use it as a fixture, so it looks alive.
// It is not. This banner sits on the file rather than the package because the
// package around it (`domain_core` / `data_core`) IS framework — keep that.
//
// Full file list: `tools/sample_manifest.yaml` -> embedded_samples.cache_chain

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
