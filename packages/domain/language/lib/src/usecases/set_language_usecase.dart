import 'package:domain_core/domain_core.dart';
import 'package:injectable/injectable.dart';

import '../params/set_language_params.dart';
import '../repositories/i_language_repository.dart';

@injectable
class SetLanguageUseCase extends BaseUseCase<void, SetLanguageParams> {
  SetLanguageUseCase(this._repository);

  final ILanguageRepository _repository;

  @override
  Result<void> call(SetLanguageParams params) {
    return _repository.setLanguage(params.languageCode);
  }
}
