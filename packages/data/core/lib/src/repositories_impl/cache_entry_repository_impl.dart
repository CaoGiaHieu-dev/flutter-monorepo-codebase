import 'package:core_database/core_database.dart';
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
    return execute<CacheEntry?, CacheEntryEntity?>(
      () => _local.getEntry(key),
      mapper: (row) => row == null ? null : _toEntity(row),
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
    return execute<List<CacheEntry>, List<CacheEntryEntity>>(
      _local.getAll,
      mapper: (rows) => rows.map(_toEntity).toList(),
    );
  }

  CacheEntryEntity _toEntity(CacheEntry row) {
    return CacheEntryEntity(
      key: row.key,
      value: row.value,
      updatedAt: row.updatedAt,
    );
  }
}
