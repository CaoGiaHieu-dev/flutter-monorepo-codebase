import 'package:domain_core/domain_core.dart';

import '../entities/cache_entry_entity.dart';
import '../params/cache_entry_params.dart';

/// SAMPLE — repository contract for cached rows. Implemented in `data_cache`.
abstract class ICacheEntryRepository {
  Future<Result<CacheEntryEntity?>> getByKey(String key);

  Future<Result<void>> save(CacheEntryParams params);
}
