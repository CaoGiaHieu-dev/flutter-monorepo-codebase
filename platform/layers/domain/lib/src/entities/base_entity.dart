import 'package:freezed_annotation/freezed_annotation.dart';

import '../utils/domain_constants.dart';

part 'base_entity.freezed.dart';
part 'base_entity.g.dart';

@Freezed(genericArgumentFactories: true)
abstract class BaseEntity<T> with _$BaseEntity<T> {
  const BaseEntity._(); // private constructor for getters

  const factory BaseEntity({
    @JsonKey(name: 'statusCode') @Default(200) int statusCode,
    @JsonKey(name: 'data') T? data,
    @JsonKey(name: 'message') String? message,
  }) = _BaseEntity<T>;

  /// Whether the envelope reports success: any 2xx. A create answered `201`
  /// or an action answered `204` is as successful as a `200`; only an
  /// envelope reporting a 1xx, 3xx, 4xx or 5xx is [hasError].
  bool get isSuccess =>
      statusCode >= DomainConstants.SUCCESS_STATUS_CODE &&
      statusCode < DomainConstants.SUCCESS_STATUS_CEILING;
  bool get hasError => !isSuccess;

  factory BaseEntity.fromJson(
    Map<String, dynamic> json,
    T Function(Object? json) fromJsonT,
  ) => _$BaseEntityFromJson(json, fromJsonT);
}
