// SAMPLE (cache_chain) — nothing in the app uses it: copy the shape for a real
// table, or delete it. What to delete and edit: tools/sample_manifest.yaml.

import 'package:injectable/injectable.dart';

import '../params/cache_entry_params.dart';
import '../repositories/i_cache_entry_repository.dart';
import '../repositories/result.dart';
import 'base_use_case.dart';

@injectable
class SaveCacheEntryUseCase extends BaseUseCase<void, CacheEntryParams> {
  SaveCacheEntryUseCase(this._repository);

  final ICacheEntryRepository _repository;

  @override
  Future<Result<void>> call(CacheEntryParams params) {
    return _repository.save(params);
  }
}
