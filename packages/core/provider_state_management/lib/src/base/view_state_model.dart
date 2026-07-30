part of 'base_provider.dart';

@freezed
abstract class ErrorState with _$ErrorState {
  const factory ErrorState.custom() = IErrorState;
  const factory ErrorState.raw(Map<String, dynamic> json) = _RawErrorState;

  factory ErrorState.fromJson(Map<String, dynamic> json) =>
      _$ErrorStateFromJson(json);
}

typedef ErrorStateDeserializer = ErrorState Function(Map<String, dynamic> json);

class ErrorStateRegistry {
  static final Map<String, ErrorStateDeserializer> _deserializers = {};

  static void register(String type, ErrorStateDeserializer deserializer) {
    _deserializers[type] = deserializer;
  }

  static ErrorState? fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String?;
    final deserializer = _deserializers[type];
    if (deserializer != null) {
      return deserializer(json);
    }
    return ErrorState.raw(json);
  }
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
@Freezed(genericArgumentFactories: true)
abstract class ViewStateModel<T> with _$ViewStateModel<T> {
  const ViewStateModel._();
  const factory ViewStateModel({
    /// The current state of the view model.
    @JsonKey(fromJson: _stateFromJson, toJson: _stateToJson)
    @Default(ViewState.initial())
    ViewState state,

    /// The data associated with the current state.
    T? data,

    /// The optional message associated with the state.
    String? message,
  }) = _ViewStateModel<T>;

  /// Creates a [ViewStateModel] instance from a JSON map.
  factory ViewStateModel.fromJson(
    Map<String, dynamic> json,
    T Function(Object?) fromJsonT,
  ) => _$ViewStateModelFromJson(json, fromJsonT);
}

ViewState _stateFromJson(Object? json) {
  if (json is Map<String, dynamic>) {
    final stateType = json['state'] as String?;
    if (stateType == 'error') {
      final errorJson = json['error'] as Map<String, dynamic>?;
      final errorState = errorJson != null
          ? ErrorStateRegistry.fromJson(errorJson)
          : null;
      return ViewState.error(error: errorState);
    }
    return switch (stateType) {
      'initial' => const ViewState.initial(),
      'loading' => const ViewState.loading(),
      'success' => const ViewState.success(),
      _ => const ViewState.initial(),
    };
  }
  if (json is String) {
    return switch (json) {
      'initial' => const ViewState.initial(),
      'loading' => const ViewState.loading(),
      'success' => const ViewState.success(),
      'error' => const ViewState.error(),
      _ => const ViewState.initial(),
    };
  }
  return const ViewState.initial();
}

Object? _stateToJson(ViewState state) {
  return state.when(
    initial: () => {'state': 'initial'},
    loading: () => {'state': 'loading'},
    success: () => {'state': 'success'},
    loadingMore: () => {'state': 'loadingMore'},
    error: (error) => {
      'state': 'error',
      if (error != null) 'error': error.toJson(),
    },
  );
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
