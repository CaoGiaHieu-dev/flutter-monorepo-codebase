import 'package:domain_core/domain_core.dart';
import 'package:injectable/injectable.dart';

import '../repositories/i_language_repository.dart';

@injectable
class GetLanguageUseCase extends BaseUseCase<String, NoParams> {
  GetLanguageUseCase(this._repository);

  final ILanguageRepository _repository;

  @override
  Result<String> call(NoParams params) {
    return _repository.getLanguage();
  }
}
