import 'package:freezed_annotation/freezed_annotation.dart';

part 'no_params.freezed.dart';

/// Empty parameters class for use cases that don't require parameters
@freezed
abstract class NoParams with _$NoParams {
  const NoParams._();
  const factory NoParams() = _NoParams;
}
