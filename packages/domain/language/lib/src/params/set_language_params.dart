import 'package:freezed_annotation/freezed_annotation.dart';

part 'set_language_params.freezed.dart';
part 'set_language_params.g.dart';

@freezed
abstract class SetLanguageParams with _$SetLanguageParams {
  const factory SetLanguageParams({required String languageCode}) =
      _SetLanguageParams;

  factory SetLanguageParams.fromJson(Map<String, dynamic> json) =>
      _$SetLanguageParamsFromJson(json);
}
