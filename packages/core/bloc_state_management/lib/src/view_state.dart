import 'package:core_common/core_common.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'view_state.freezed.dart';

/// Standardized generic UI states for Bloc/Cubit
@freezed
abstract class ViewState<T> with _$ViewState<T> {
  const ViewState._();
  const factory ViewState.initial() = _Initial<T>;
  const factory ViewState.loading() = _Loading<T>;
  const factory ViewState.success(T data) = _Success<T>;
  const factory ViewState.error(AppFailure error) = _Error<T>;

  T? get data => mapOrNull(success: (s) => s.data);
}
