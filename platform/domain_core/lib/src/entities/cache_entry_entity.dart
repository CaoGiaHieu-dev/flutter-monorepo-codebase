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

import 'package:freezed_annotation/freezed_annotation.dart';

part 'cache_entry_entity.freezed.dart';

/// Domain entity for a locally cached key-value row stored in Drift.
@freezed
abstract class CacheEntryEntity with _$CacheEntryEntity {
  const factory CacheEntryEntity({
    required String key,
    required String value,
    required DateTime updatedAt,
  }) = _CacheEntryEntity;
}
