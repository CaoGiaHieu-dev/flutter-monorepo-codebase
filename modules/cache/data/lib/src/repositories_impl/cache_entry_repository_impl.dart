import 'package:data_core/data_core.dart';
import 'package:domain_cache/domain_cache.dart';
import 'package:domain_core/domain_core.dart';
import 'package:injectable/injectable.dart';

import '../data_sources/local/cache_entry_local_data_source.dart';
import '../models/cache_entry_model.dart';

/// SAMPLE — wraps the local data source in `execute()` so nothing throws past
/// the data layer, and maps [CacheEntryModel] to the domain entity.
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
}
