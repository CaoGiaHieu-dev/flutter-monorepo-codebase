// SAMPLE (cache_chain) — nothing in the app uses it: copy the shape for a real
// table, or delete it. What to delete and edit: tools/sample_manifest.yaml.

import 'package:domain_core/domain_core.dart';
import 'package:injectable/injectable.dart';

import '../../data_core.dart';

@LazySingleton(as: ICacheEntryRepository)
class CacheEntryRepositoryImpl extends IBaseRepository
    implements ICacheEntryRepository {
  CacheEntryRepositoryImpl(this._local);

  final ICacheEntryLocalDataSource _local;

  @override
  Future<Result<CacheEntryEntity?>> getByKey(String key) {
    return execute<CacheEntryModel?, CacheEntryEntity?>(
      () => _local.getEntry(key),
      mapper: (model) => model?.toEntity(),
    );
  }

  @override
  Future<Result<void>> save(CacheEntryParams params) {
    return execute<void, void>(() => _local.save(params.key, params.value));
  }

  @override
  Future<Result<void>> delete(String key) {
    return execute<void, void>(() => _local.delete(key));
  }

  @override
  Future<Result<List<CacheEntryEntity>>> getAll() {
    return execute<List<CacheEntryModel>, List<CacheEntryEntity>>(
      _local.getAll,
      mapper: (models) => models.map((model) => model.toEntity()).toList(),
    );
  }
}
