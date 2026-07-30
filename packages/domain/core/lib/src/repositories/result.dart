import 'dart:async';

import 'package:core_common/core_common.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../entities/base/base_entity.dart';
import '../entities/base/paginate_entity.dart';

part 'result.freezed.dart';

/// Type alias for a result containing a BaseEntity
typedef BaseResult<T> = Result<BaseEntity<T>>;
typedef BasePaginateResult<T> = Result<BaseEntity<PaginatedEntity<T>>>;

/// A sealed class representing the result of an operation, which can be a
/// [Success], [Failure], [None], or [Cancel].
///
/// Usage with Dart 3 pattern matching:
/// ```dart
/// switch (result) {
///   case Success(:final data):
///     print('Data: $data');
///   case Failure(:final error):
///     print('Error: ${error.message}');
///   case None():
///     print('No result');
///   case Cancel():
///     print('Cancelled');
/// }
/// ```
@freezed
sealed class Result<T> with _$Result<T> {
  const Result._();

  const factory Result.success([T? data]) = Success<T>;
  const factory Result.failure(AppFailure error) = Failure<T>;
  const factory Result.none() = None<T>;
  const factory Result.cancel() = Cancel<T>;

  // ---------------------------------------------------------------------------
  // Convenience getters
  // ---------------------------------------------------------------------------

  /// Returns `true` if the result is a [Success].
  bool get isSuccess => this is Success<T>;

  /// Returns `true` if the result is a [Failure].
  bool get isFailure => this is Failure<T>;

  /// Returns the data if the result is a [Success], otherwise returns `null`.
  T? get dataOrNull => switch (this) {
    Success<T>(:final data) => data,
    _ => null,
  };

  /// Returns the [AppFailure] if the result is a [Failure], otherwise `null`.
  AppFailure? get errorOrNull => switch (this) {
    Failure<T>(:final error) => error,
    _ => null,
  };

  // ---------------------------------------------------------------------------
  // Functional API
  // ---------------------------------------------------------------------------

  /// Async-aware exhaustive handler.
  ///
  /// Use this when one or more branches perform async work.
  /// For fully synchronous branches, prefer the Freezed-generated [when].
  Future<R> whenAsync<R>({
    required FutureOr<R> Function(T? data) success,
    required FutureOr<R> Function(AppFailure error) failure,
    required FutureOr<R> Function() none,
    required FutureOr<R> Function() cancel,
  }) async {
    return switch (this) {
      Success<T>(:final data) => await success(data),
      Failure<T>(:final error) => await failure(error),
      None<T>() => await none(),
      Cancel<T>() => await cancel(),
    };
  }

  /// Transforms the data of a [Success] while preserving other variants.
  Result<R> mapData<R>(R Function(T? data) transform) {
    return when(
      success: (data) => Result.success(transform(data)),
      failure: Result.failure,
      none: Result.none,
      cancel: Result.cancel,
    );
  }

  /// Chains another [Result]-returning operation on [Success].
  ///
  /// If this is a [Success], calls [transform] with the data and returns
  /// its result. Otherwise, propagates the current non-success variant.
  FutureOr<Result<R>> flatMap<R>(
    FutureOr<Result<R>> Function(T? data) transform,
  ) {
    return when(
      success: transform,
      failure: Result.failure,
      none: Result.none,
      cancel: Result.cancel,
    );
  }

  /// Returns the data if [Success], otherwise returns [defaultValue].
  T? getOrElse(T defaultValue) => dataOrNull ?? defaultValue;

  /// Returns the data if [Success], otherwise throws the [AppFailure].
  ///
  /// Throws [StateError] if the result is neither [Success] nor [Failure].
  T? getOrThrow() {
    return switch (this) {
      Success<T>(:final data) => data,
      Failure<T>(:final error) => throw error,
      _ => throw StateError('Result is neither Success nor Failure: $this'),
    };
  }
}
