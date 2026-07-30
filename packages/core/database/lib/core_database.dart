/// Core Database — relational local persistence with Drift.
///
/// Provides:
/// - [AppDatabase] — Drift database running on a background isolate
/// - [CacheEntriesDao] — example DAO for key-value cache rows
/// - [DatabaseConnectionFactory] — opens SQLite with [NativeDatabase.createInBackground]
library core_database;

// Auto-generated exports, do not edit manually.
export 'di/di.dart';
export 'src/src.dart';
