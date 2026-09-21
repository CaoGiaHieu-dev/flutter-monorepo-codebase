import 'package:freezed_annotation/freezed_annotation.dart';

import 'base_entity.dart';

part 'paginate_entity.freezed.dart';
part 'paginate_entity.g.dart';

typedef BaseEntityPaginate<T> = BaseEntity<PaginatedEntity<T>>;

@Freezed(genericArgumentFactories: true)
abstract class PaginatedEntity<T> with _$PaginatedEntity<T> {
  const PaginatedEntity._();
  const factory PaginatedEntity({
    @JsonKey(name: 'items') @Default([]) List<T> data,
    @JsonKey(name: 'meta') @Default(MetaPaginate()) MetaPaginate meta,
  }) = _PaginatedEntity<T>;

  factory PaginatedEntity.fromJson(
    Map<String, dynamic> json,
    T Function(Object?) fromJsonT,
  ) => _$PaginatedEntityFromJson(json, fromJsonT);
}

@freezed
abstract class MetaPaginate with _$MetaPaginate {
  const MetaPaginate._();
  const factory MetaPaginate({
    @JsonKey(name: 'totalItems') @Default(0) int totalItems,
    @JsonKey(name: 'itemCount') @Default(0) int itemCount,
    @JsonKey(name: 'itemsPerPage') @Default(0) int itemsPerPage,
    @JsonKey(name: 'totalPages') @Default(0) int totalPages,
    @JsonKey(name: 'currentPage') @Default(0) int currentPage,
  }) = _MetaPaginate;

  factory MetaPaginate.fromJson(Map<String, dynamic> json) =>
      _$MetaPaginateFromJson(json);
}
