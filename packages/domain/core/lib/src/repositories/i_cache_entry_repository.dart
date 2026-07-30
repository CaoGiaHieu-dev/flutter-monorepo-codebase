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
