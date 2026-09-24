import 'package:freezed_annotation/freezed_annotation.dart';

part 'failures.freezed.dart';
part 'failures.g.dart';

/// Base class for all application failures.
///
/// This abstract class represents the result of failed operations in the
/// application. Unlike exceptions, failures are expected outcomes that
/// should be handled gracefully by the application logic.
@Freezed(genericArgumentFactories: true)
sealed class AppFailure<T> with _$AppFailure<T> {
  /// Failure that occurs during network operations.
  const factory AppFailure.network({
    required String message,
    int? code,
    T? data,
  }) = NetworkFailure<T>;

  /// Failure that occurs when server returns an error response.
  const factory AppFailure.server({
    required String message,
    int? code,
    T? data,
  }) = ServerFailure<T>;

  /// Failure that occurs during authentication or authorization.
  const factory AppFailure.auth({required String message, int? code, T? data}) =
      AuthFailure<T>;

  /// Failure that occurs during local storage operations.
  const factory AppFailure.storage({
    required String message,
    int? code,
    T? data,
  }) = StorageFailure<T>;

  /// Failure that occurs during data validation.
  const factory AppFailure.validation({
    required String message,
    int? code,
    T? data,
    String? field,
  }) = ValidationFailure<T>;

  /// Failure that occurs during data parsing or serialization.
  const factory AppFailure.parse({
    required String message,
    int? code,
    T? data,
  }) = ParseFailure<T>;

  /// Failure that occurs during cache operations.
  const factory AppFailure.cache({
    required String message,
    int? code,
    T? data,
  }) = CacheFailure<T>;

  /// Failure that occurs during external service operations.
  const factory AppFailure.service({
    required String message,
    int? code,
    T? data,
  }) = ServiceFailure<T>;

  factory AppFailure.fromJson(
    Map<String, dynamic> json,
    T Function(Object?) fromJsonT,
  ) => _$AppFailureFromJson(json, fromJsonT);
}
