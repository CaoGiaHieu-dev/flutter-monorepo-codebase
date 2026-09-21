// SAMPLE CODE — safe to delete.
//
// Part of the `cache_chain` sample: one complete vertical slice (table -> DAO
// -> data source -> repository -> entity -> use cases) kept as a copy-me
// template for your first real table.
//
// Nothing in the app consumes it. `unused_checker` will not flag it because it
// is registered in DI, and the tests use it as a fixture, so it looks alive.
// It is not. This banner sits on the file rather than the package because the
// package around it (`domain_core` / `data_core`) IS framework — keep that.
//
// Full file list: `tools/sample_manifest.yaml` -> embedded_samples.cache_chain

import 'package:domain_core/domain_core.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../database/cache_database.dart';
import 'base_model.dart';

part 'cache_entry_model.freezed.dart';

/// Data-layer representation of a row in the `cache_entries` table.
///
/// Exists so Drift stays an implementation detail of this package: the
/// generated [CacheEntry] row class is converted here, at the boundary, and
/// never appears in `ICacheEntryLocalDataSource`'s signatures. Without this
/// model the repository — and anything importing `data_core` — would be
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
