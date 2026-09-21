import 'package:freezed_annotation/freezed_annotation.dart';

import 'login_params.dart';

part 'complete_login_flow_params.freezed.dart';

@freezed
abstract class CompleteLoginFlowParams with _$CompleteLoginFlowParams {
  const CompleteLoginFlowParams._();
  const factory CompleteLoginFlowParams({
    required LoginParams loginParams,
    @Default(false) bool rememberUser,
  }) = _CompleteLoginFlowParams;
}
