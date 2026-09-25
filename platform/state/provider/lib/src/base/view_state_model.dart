part of 'base_provider.dart';

/// The error a [ViewState.error] carries.
///
/// A feature attaches its own error by extending [CustomErrorState] with a
/// Freezed union (see `AuthErrorState`) and mapping `AppFailure` into it
/// through `OperationConfig.errorStateBuilder`.
@freezed
abstract class ErrorState with _$ErrorState {
  const factory ErrorState.custom() = CustomErrorState;
}

@freezed
abstract class ViewState with _$ViewState {
  const ViewState._();
  const factory ViewState.initial() = _Initial;
  const factory ViewState.loading() = _Loading;
  const factory ViewState.success() = _Success;
  const factory ViewState.error({ErrorState? error}) = _Error;
  const factory ViewState.loadingMore() = _LoadingMore;

  bool get isInitial => this is _Initial;
  bool get isLoading => this is _Loading;
  bool get isSuccess => this is _Success;
  bool get isError => this is _Error;
  bool get isLoadingMore => this is _LoadingMore;
}

/// Class representing the state of the view model.
///
/// This class contains the current state, data, and optional message.
@freezed
abstract class ViewStateModel<T> with _$ViewStateModel<T> {
  const ViewStateModel._();
  const factory ViewStateModel({
    /// The current state of the view model.
    @Default(ViewState.initial()) ViewState state,

    /// The data associated with the current state.
    T? data,

    /// The optional message associated with the state.
    String? message,
  }) = _ViewStateModel<T>;
}

extension ViewStateModelExt<T> on ViewStateModel<T> {
  /// Returns `true` if the state is [ViewState.loading], otherwise `false`.
  bool get isLoading => state.isLoading;

  /// Returns `true` if the state is [ViewState.success], otherwise `false`.
  bool get isSuccess => state.isSuccess;

  /// Returns `true` if the state is [ViewState.error], otherwise `false`.
  bool get isError => state.isError;

  /// Returns `true` if the state is [ViewState.initial], otherwise `false`.
  bool get isInitial => state.isInitial;
}
