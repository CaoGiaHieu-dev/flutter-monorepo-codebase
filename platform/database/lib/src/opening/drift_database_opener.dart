import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../connection/database_connection_factory.dart';
import '../utils/database_constants.dart';

/// Builds a drift database from an executor.
///
/// Each owning package supplies its own constructor here, which is what lets
/// this package open a database without knowing any concrete database class.
typedef DriftDatabaseBuilder<T extends GeneratedDatabase> = T Function(
  QueryExecutor executor,
);

/// Opens a drift database on a background isolate, with recovery.
///
/// This is the mechanism half of persistence: it knows how to open a SQLite
/// file safely, but nothing about tables, DAOs or schemas. A package that
/// owns data declares its own [GeneratedDatabase] and opens it through
/// [open].
abstract final class DriftDatabaseOpener {
  /// Opens [build]'s database on a background isolate.
  ///
  /// The connection is verified before the future completes, so a database
  /// whose file is unreadable fails here rather than at the first query.
  ///
  /// ## Corruption recovery
  ///
  /// Callers usually register this with `@preResolve`, so anything thrown
  /// here aborts `configureDependencies()` and the app cannot start. To avoid
  /// a permanent crash loop on a damaged file, a failure whose message
  /// matches [DatabaseConstants.CORRUPTION_ERROR_MARKERS] causes the file to
  /// be **moved aside** (see
  /// [DatabaseConnectionFactory.quarantineDatabaseFile]) and reopened empty.
  ///
  /// Recovery is deliberately narrow. Any failure that also looks like an
  /// environment problem — no permission, full disk, transient I/O, listed in
  /// [DatabaseConstants.ENVIRONMENT_ERROR_MARKERS] — is rethrown with the
  /// database untouched. Surfacing a startup error is preferable to
  /// discarding data that was never actually corrupt, and the quarantined
  /// file is renamed rather than deleted so the bytes remain recoverable.
  static Future<T> open<T extends GeneratedDatabase>(
    DriftDatabaseBuilder<T> build, {
    required String fileName,
    int readPool = DatabaseConstants.DEFAULT_READ_POOL,
  }) async {
    try {
      return await _openVerified(build, fileName: fileName, readPool: readPool);
    } catch (error, stackTrace) {
      if (!isCorruptionError(error)) rethrow;

      debugPrint(
        'core_database: database file "$fileName" is corrupt and will be '
        'quarantined as "$fileName${DatabaseConstants.CORRUPT_FILE_SUFFIX}", '
        'then recreated empty. Stored data is lost. Error: $error',
      );
      debugPrintStack(stackTrace: stackTrace, label: 'core_database');

      await DatabaseConnectionFactory.quarantineDatabaseFile(
        fileName: fileName,
      );
      return _openVerified(build, fileName: fileName, readPool: readPool);
    }
  }

  /// Opens the database and forces the connection to be established.
  ///
  /// [DatabaseConnectionFactory.createBackgroundExecutor] is lazy: it does
  /// not touch the file until the first statement runs. The probe query below
  /// makes drift open the file, run migrations and execute `beforeOpen`, so a
  /// broken database surfaces here instead of at some unrelated call site.
  static Future<T> _openVerified<T extends GeneratedDatabase>(
    DriftDatabaseBuilder<T> build, {
    required String fileName,
    required int readPool,
  }) async {
    final executor = await DatabaseConnectionFactory.createBackgroundExecutor(
      fileName: fileName,
      readPool: readPool,
    );
    final database = build(executor);
    try {
      await database.customSelect('SELECT 1').get();
      return database;
    } catch (_) {
      // Release the isolate before the failure propagates, otherwise a
      // retry would leak the background worker of this attempt.
      await database.close();
      rethrow;
    }
  }

  /// Whether [error] indicates a corrupt database file, and nothing else.
  ///
  /// Exposed for testing: this predicate decides whether a user's database
  /// may be moved aside, so it is verified directly rather than only through
  /// a real corrupt file.
  ///
  /// The `sqlite3` package is not a declared dependency of `core_database`,
  /// so the typed `SqliteException` (and its `extendedResultCode`) is not
  /// available here and the message is matched instead. The predicate is
  /// therefore biased towards *not* recovering: an environment marker vetoes
  /// a corruption match.
  @visibleForTesting
  static bool isCorruptionError(Object error) {
    final message = error.toString().toLowerCase();

    final looksLikeEnvironment = DatabaseConstants.ENVIRONMENT_ERROR_MARKERS
        .any(message.contains);
    if (looksLikeEnvironment) return false;

    return DatabaseConstants.CORRUPTION_ERROR_MARKERS.any(message.contains);
  }
}
