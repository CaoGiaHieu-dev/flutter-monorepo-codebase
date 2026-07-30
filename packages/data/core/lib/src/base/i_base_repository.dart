import 'dart:async';

import 'package:core_common/core_common.dart';
import 'package:domain_core/domain_core.dart';

abstract class IBaseRepository {
  /// Wrapper function for executing asynchronous operations (API, DB, etc.).
  ///
  /// - [request]: The actual async operation that returns a [Future] of type [R].
  /// - [mapper]: An optional mapping function to transform the result of type [R] to the domain entity of type [T].
  /// - [onSuccess]: Optional side effect callback executed only when the operation succeeds.
  /// - [onFailure]: Optional side effect callback executed only when the operation fails.
  /// - [successCondition]: Custom condition to evaluate if the response should be considered a success. If omitted, defaults to true (assuming no exception was thrown).
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

        // Handle void, Null, or nullable types when no mapping is needed
        if (null is T && mapper == null) {
          return Success(null as T);
        }

        if (response != null) {
          final mappedData = mapper != null
              ? mapper(response)
              : (response as T);
          return Success(mappedData);
        } else {
          try {
            return Success(response as T);
          } catch (_) {
            return Failure(
              ErrorHandler.serverFailure('Response data is null', null),
            );
          }
        }
      }

      await onFailure?.call(response);
      return Failure(
        ErrorHandler.serverFailure(
          'Request failed based on success condition',
          null,
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

      // Handle void, Null, or nullable types when no mapping is needed
      if (null is T && mapper == null) {
        return Success(null as T);
      }

      if (result != null) {
        final mappedData = mapper != null ? mapper(result) : (result as T);
        return Success(mappedData);
      } else {
        try {
          return Success(result as T);
        } catch (_) {
          return Failure(
            ErrorHandler.serverFailure('Operation returned null', null),
          );
        }
      }
    } catch (e) {
      onFailure?.call(e);
      return Failure(ErrorHandler.handleError(e));
    }
  }
}
