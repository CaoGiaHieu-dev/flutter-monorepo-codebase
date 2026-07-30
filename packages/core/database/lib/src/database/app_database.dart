import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';

import '../connection/database_connection_factory.dart';
import 'tables/cache_entries_table.dart';

part 'app_database.g.dart';
part 'dao/cache_entries_dao.dart';

/// Application Drift database.
///
/// Open via [AppDatabase.open] — the connection is hosted on a background
/// isolate created by [NativeDatabase.createInBackground].
@DriftDatabase(tables: [CacheEntries], daos: [CacheEntriesDao])
class AppDatabase extends _$AppDatabase {
  AppDatabase._(super.e);

  /// Opens the database file on a background isolate.
  static Future<AppDatabase> open({
    String fileName = DatabaseConnectionFactory.defaultFileName,
    int readPool = 1,
  }) async {
    final executor = await DatabaseConnectionFactory.createBackgroundExecutor(
      fileName: fileName,
      readPool: readPool,
    );
    return AppDatabase._(executor);
  }

  /// In-memory database for unit tests (runs on the current isolate).
  @visibleForTesting
  factory AppDatabase.forTesting([QueryExecutor? executor]) {
    return AppDatabase._(executor ?? NativeDatabase.memory());
  }

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
    },
  );
}
