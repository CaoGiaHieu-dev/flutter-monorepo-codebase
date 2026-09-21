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
