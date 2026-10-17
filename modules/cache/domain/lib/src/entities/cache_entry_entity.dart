import 'package:freezed_annotation/freezed_annotation.dart';

part 'cache_entry_entity.freezed.dart';

/// A locally cached key-value row.
@freezed
abstract class CacheEntryEntity with _$CacheEntryEntity {
  const CacheEntryEntity._();

  const factory CacheEntryEntity({
    required String key,
    required String value,
    required DateTime updatedAt,
  }) = _CacheEntryEntity;
}
