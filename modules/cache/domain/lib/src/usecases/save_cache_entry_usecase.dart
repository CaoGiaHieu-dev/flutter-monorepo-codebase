import 'package:domain_core/domain_core.dart';
import 'package:injectable/injectable.dart';

import '../params/cache_entry_params.dart';
import '../repositories/i_cache_entry_repository.dart';

@injectable
class SaveCacheEntryUseCase extends BaseUseCase<void, CacheEntryParams> {
  SaveCacheEntryUseCase(this._repository);

  final ICacheEntryRepository _repository;

  @override
  Future<Result<void>> call(CacheEntryParams params) {
    return _repository.save(params);
  }
}
