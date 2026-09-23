import 'package:data_core/data_core.dart';
import 'package:domain_cache/domain_cache.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../database/cache_database.dart';

part 'cache_entry_model.freezed.dart';

/// Data-layer representation of a row in the `cache_entries` table.
///
/// Exists so Drift stays an implementation detail of this package: the
/// generated [CacheEntry] row class is converted here, at the boundary, and
/// never appears in `ICacheEntryLocalDataSource`'s signatures. Without this
/// model the repository — and anything importing `data_cache` — would be
/// coupled to Drift's generated code.
///
/// Deliberately not `json_serializable`: rows come from SQLite, not from an
/// API payload, so there is no JSON contract to honour.
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

  /// Maps a Drift row into the data-layer model.
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
