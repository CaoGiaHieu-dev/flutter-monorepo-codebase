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

import '../entities/cache_entry_entity.dart';
import '../params/cache_entry_params.dart';
import 'result.dart';

/// Repository contract for Drift-backed cache rows.
///
/// Implemented in `data_core` via [CacheEntryRepositoryImpl].
abstract class ICacheEntryRepository {
  Future<Result<CacheEntryEntity?>> getByKey(String key);

  Future<Result<void>> save(CacheEntryParams params);

  Future<Result<void>> delete(String key);

  Future<Result<List<CacheEntryEntity>>> getAll();
}
