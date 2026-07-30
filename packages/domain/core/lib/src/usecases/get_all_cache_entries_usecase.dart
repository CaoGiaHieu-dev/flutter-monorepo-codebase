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
