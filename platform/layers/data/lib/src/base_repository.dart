import 'dart:async';

import 'package:domain_core/domain_core.dart';
import 'package:platform_kernel/platform_kernel.dart';

/// Base class of every `RepositoryImpl`: [execute] and [executeSync] turn
/// an operation into a [Result], so nothing throws past the data layer.
abstract class BaseRepository {
  /// Wrapper function for executing asynchronous operations (API, DB, etc.).
  ///
  /// - [request]: The actual async operation that returns a [Future] of type [R].
  /// - [mapper]: An optional mapping function to transform the result of type [R] to the domain entity of type [T].
  /// - [onSuccess]: Optional side effect callback executed only when the operation succeeds.
  /// - [onFailure]: Optional side effect callback executed only when the operation fails.
  /// - [successCondition]: Custom condition to evaluate if the response should be considered a success. If omitted, defaults to true (assuming no exception was thrown).
  ///   A rejected response fails with `ServerFailure(code: ErrorCodes.RESPONSE_REJECTED)`,
  ///   carrying the envelope's `message` when the response is a [BaseEntity] reporting an error.
  Future<Result<T>> execute<R, T>(
    Future<R> Function() request, {
    T Function(R data)? mapper,
    FutureOr<void> Function(R response)? onSuccess,
    FutureOr<void> Function(R response)? onFailure,
    bool Function(R response)? successCondition,
  }) async {
    try {
      final response = await request.call();

      final isSuccess = successCondition?.call(response) ?? true;

      if (isSuccess) {
        await onSuccess?.call(response);
        return _toResult<R, T>(response, mapper);
      }

      await onFailure?.call(response);
      // The server answered; the success condition rejected what it said.
      // Coded apart from HTTP 5xx so a caller can tell this verdict from a
      // transient fault — it used to be `serverFailure(…, null)`, i.e. code
      // 500, which the auth gateway read as "server down, keep the session".
      return Failure(
        ErrorHandler.responseRejectedFailure(
          response is BaseEntity && response.hasError ? response.message : null,
        ),
      );
    } catch (e) {
      return Failure(ErrorHandler.handleError(e));
    }
  }

  /// Wrapper function for executing synchronous/local operations.
  ///
  /// - [action]: The actual synchronous operation that returns a value of type [R].
  /// - [mapper]: An optional mapping function to transform the result of type [R] to the domain entity of type [T].
  /// - [onSuccess]: Optional side effect callback executed only when the operation succeeds.
  /// - [onFailure]: Optional side effect callback executed only when the operation throws an exception.
  Result<T> executeSync<R, T>(
    R Function() action, {
    T Function(R data)? mapper,
    void Function(R result)? onSuccess,
    void Function(Object error)? onFailure,
  }) {
    try {
      final result = action.call();
      onSuccess?.call(result);
      return _toResult<R, T>(result, mapper, 'Operation returned null');
    } catch (e) {
      onFailure?.call(e);
      return Failure(ErrorHandler.handleError(e));
    }
  }

  /// [value] as a [Success], mapped through [mapper] when one is given.
  ///
  /// A `null` [value] is a success only when [T] is nullable — a `void`,
  /// `Null` or `T?` operation — and is never handed to [mapper]; for a
  /// non-nullable [T] it is an empty-response failure carrying
  /// [emptyMessage]. A non-null [value] with no [mapper] must already be a
  /// [T]; the cast throws otherwise, and the caller's `catch` classifies it.
  Result<T> _toResult<R, T>(
    R value,
    T Function(R data)? mapper, [
    String? emptyMessage,
  ]) {
    if (value == null) {
      return null is T
          ? Success<T>(null)
          : Failure<T>(ErrorHandler.emptyResponseFailure(emptyMessage));
    }
    return Success<T>(mapper != null ? mapper(value) : value as T);
  }
}
