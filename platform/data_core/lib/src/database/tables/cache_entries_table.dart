// SAMPLE (cache_chain) — nothing in the app uses it: copy the shape for a real
// table, or delete it. What to delete and edit: tools/sample_manifest.yaml.

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
