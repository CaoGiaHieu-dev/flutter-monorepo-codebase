import 'package:freezed_annotation/freezed_annotation.dart';

part 'base_request.freezed.dart';
part 'base_request.g.dart';

@Freezed(genericArgumentFactories: true)
abstract class BaseRequest<T> with _$BaseRequest<T> {
  const BaseRequest._();
  const factory BaseRequest({
    @JsonKey(name: 'page') @Default(1) int page,
    @JsonKey(name: 'pageSize') @Default(25) int pageSize,
    @JsonKey(name: 'data') T? data,
  }) = _BaseRequest<T>;

  factory BaseRequest.fromJson(
    Map<String, dynamic> json,
    T Function(Object? json) fromJsonT,
  ) => _$BaseRequestFromJson(json, fromJsonT);
}
