import 'package:domain_core/domain_core.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'bloc_view_state.freezed.dart';

/// Standardized generic UI state for Bloc/Cubit screens.
///
/// Named `BlocViewState` — not `ViewState` — on purpose: the Provider branch
/// (`provider_state_management`) exports its own, **semantically different**
/// `ViewState` used inside `ViewStateModel<T>`. Both barrels are public, so a
/// file importing the two packages together would hit a name collision if the
/// two types shared a name.
///
/// Differences from the Provider `ViewState`:
/// - carries its payload directly (`success(T data)`), whereas the Provider
///   variant is data-less and keeps data on `ViewStateModel<T>`
/// - `error` requires an [AppFailure]; the Provider variant takes a nullable
///   `ErrorState`
/// - has no `loadingMore` variant
///
/// This type is **optional**. A screen with richer UI needs may declare its own
/// Freezed state and use `BaseBloc<Event, CustomState>` instead.
@freezed
abstract class BlocViewState<T> with _$BlocViewState<T> {
  const BlocViewState._();
  const factory BlocViewState.initial() = _Initial<T>;
  const factory BlocViewState.loading() = _Loading<T>;
  const factory BlocViewState.success(T data) = _Success<T>;
  const factory BlocViewState.error(AppFailure error) = _Error<T>;

  T? get data => mapOrNull(success: (s) => s.data);
}
