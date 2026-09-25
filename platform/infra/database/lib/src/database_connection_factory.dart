import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart' show Database;

import 'utils/database_constants.dart';

/// Factory for opening SQLite connections on a background Drift isolate.
///
/// Uses [NativeDatabase.createInBackground] so all synchronous sqlite3 I/O
/// runs off the UI thread without manual [DriftIsolate] boilerplate.
abstract final class DatabaseConnectionFactory {
  /// Resolves the on-disk database file path inside app documents.
  static Future<File> resolveDatabaseFile({required String fileName}) async {
    final directory = await getApplicationDocumentsDirectory();
    return File(p.join(directory.path, fileName));
  }

  /// Creates a [QueryExecutor] backed by a background isolate.
  ///
  /// With [readPool] above zero drift opens one more connection per reader,
  /// each on its own isolate. `MigrationStrategy.beforeOpen` runs on the
  /// writer only, so a per-connection `PRAGMA` set there never reaches the
  /// readers; [_configureConnection] runs on every connection instead.
  static Future<QueryExecutor> createBackgroundExecutor({
    required String fileName,
    int readPool = DatabaseConstants.DEFAULT_READ_POOL,
  }) async {
    final file = await resolveDatabaseFile(fileName: fileName);
    return backgroundExecutorFor(file, readPool: readPool);
  }

  /// [createBackgroundExecutor] for an explicit [file] — the part that does
  /// not need the path_provider plugin, so a unit test can open a real file.
  static QueryExecutor backgroundExecutorFor(
    File file, {
    int readPool = DatabaseConstants.DEFAULT_READ_POOL,
  }) {
    return NativeDatabase.createInBackground(
      file,
      readPool: readPool,
      setup: _configureConnection,
    );
  }

  /// Per-connection settings every connection needs, readers included.
  ///
  /// Sent to each drift isolate, so it must stay a static function that
  /// captures nothing. Without `busy_timeout` a reader meeting a lock — a
  /// WAL checkpoint, a recovery — fails at once with `SQLITE_BUSY` instead
  /// of waiting. The writer gets the same value again in `beforeOpen`, which
  /// is also where a database's own `busyTimeoutMs` override applies.
  static void _configureConnection(Database database) {
    database.execute(
      'PRAGMA busy_timeout = ${DatabaseConstants.BUSY_TIMEOUT_MS}',
    );
  }

  /// Moves an unreadable database file aside so a fresh one can be created.
  ///
  /// The file is **renamed, never deleted** — if the corruption check ever
  /// misfires the user's bytes are still recoverable from
  /// `<fileName><CORRUPT_FILE_SUFFIX>`. Only one quarantined copy is kept;
  /// an older one is replaced so repeated failures cannot fill the disk.
  ///
  /// The `-wal` / `-shm` sidecars move with it (`<fileName>.corrupt-wal`,
  /// `.corrupt-shm`): they belong to the quarantined database and must not be
  /// applied to the new one, and the WAL holds committed transactions not yet
  /// checkpointed — deleting it would lose exactly the newest data the
  /// quarantine exists to keep recoverable.
  ///
  /// Returns the quarantined [File], or `null` when there was nothing to
  /// move (the database had not been created yet).
  static Future<File?> quarantineDatabaseFile({
    required String fileName,
  }) async {
    final file = await resolveDatabaseFile(fileName: fileName);
    if (!file.existsSync()) return null;

    final quarantinePath =
        '${file.path}${DatabaseConstants.CORRUPT_FILE_SUFFIX}';
    for (final suffix in const ['', '-wal', '-shm']) {
      final previous = File('$quarantinePath$suffix');
      if (previous.existsSync()) await previous.delete();
    }

    for (final suffix in const ['-wal', '-shm']) {
      final sidecar = File('${file.path}$suffix');
      if (sidecar.existsSync()) {
        await sidecar.rename('$quarantinePath$suffix');
      }
    }

    return file.rename(quarantinePath);
  }
}
