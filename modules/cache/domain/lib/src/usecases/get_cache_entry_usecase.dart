import 'package:domain_core/domain_core.dart';
import 'package:injectable/injectable.dart';

import '../entities/cache_entry_entity.dart';
import '../repositories/i_cache_entry_repository.dart';

@injectable
class GetCacheEntryUseCase extends BaseUseCase<CacheEntryEntity?, String> {
  GetCacheEntryUseCase(this._repository);

  final ICacheEntryRepository _repository;

  @override
  Future<Result<CacheEntryEntity?>> call(String key) {
    return _repository.getByKey(key);
  }
}
