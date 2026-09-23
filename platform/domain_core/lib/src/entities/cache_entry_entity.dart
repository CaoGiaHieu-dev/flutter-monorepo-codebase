// SAMPLE (cache_chain) — nothing in the app uses it: copy the shape for a real
// table, or delete it. What to delete and edit: tools/sample_manifest.yaml.

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
