import 'package:core_common/core_common.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

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

  bool get isSuccess => statusCode == ApiStatusConstants.SUCCESS;
  bool get hasError => !isSuccess;

  factory BaseEntity.fromJson(
    Map<String, dynamic> json,
    T Function(Object? json) fromJsonT,
  ) => _$BaseEntityFromJson(json, fromJsonT);
}
