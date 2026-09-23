// SAMPLE (cache_chain) — nothing in the app uses it: copy the shape for a real
// table, or delete it. What to delete and edit: tools/sample_manifest.yaml.

import 'package:injectable/injectable.dart';

import '../../domain_core.dart';

@injectable
class GetAllCacheEntriesUseCase
    extends BaseUseCase<List<CacheEntryEntity>, NoParams> {
  GetAllCacheEntriesUseCase(this._repository);

  final ICacheEntryRepository _repository;

  @override
  Future<Result<List<CacheEntryEntity>>> call(NoParams params) {
    return _repository.getAll();
  }
}
