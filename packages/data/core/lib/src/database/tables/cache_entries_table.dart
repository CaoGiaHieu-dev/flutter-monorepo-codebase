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

import 'package:drift/drift.dart';

/// Example table — stores arbitrary string payloads keyed by a unique id.
///
/// Use this as a template when adding feature-specific tables.
class CacheEntries extends Table {
  /// Unique cache key (e.g. `home_feed`, `user_profile_draft`).
  TextColumn get key => text()();

  /// Serialized payload (JSON string, plain text, etc.).
  TextColumn get value => text()();

  /// Last write timestamp for TTL / eviction policies.
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {key};
}
