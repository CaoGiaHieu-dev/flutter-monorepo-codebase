import 'package:data_core/data_core.dart';
import 'package:domain_cache/domain_cache.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../database/cache_database.dart';

part 'cache_entry_model.freezed.dart';

/// Data-layer form of a `cache_entries` row. The generated Drift [CacheEntry]
/// is converted here, at the boundary, so Drift never leaks past `data_cache`.
/// Not `json_serializable`: rows come from SQLite, not an API payload.
@freezed
abstract class CacheEntryModel
    with _$CacheEntryModel
    implements BaseModel<CacheEntryEntity> {
  const CacheEntryModel._();

  const factory CacheEntryModel({
    required String key,
    required String value,
    required DateTime updatedAt,
  }) = _CacheEntryModel;

  factory CacheEntryModel.fromRow(CacheEntry row) {
    return CacheEntryModel(
      key: row.key,
      value: row.value,
      updatedAt: row.updatedAt,
    );
  }

  @override
  CacheEntryEntity toEntity() {
    return CacheEntryEntity(key: key, value: value, updatedAt: updatedAt);
  }
}
