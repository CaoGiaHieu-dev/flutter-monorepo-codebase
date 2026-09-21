import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../utils/database_constants.dart';

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
  static Future<QueryExecutor> createBackgroundExecutor({
    required String fileName,
    int readPool = DatabaseConstants.DEFAULT_READ_POOL,
  }) async {
    final file = await resolveDatabaseFile(fileName: fileName);
    return NativeDatabase.createInBackground(file, readPool: readPool);
  }

  /// Moves an unreadable database file aside so a fresh one can be created.
  ///
  /// The file is **renamed, never deleted** — if the corruption check ever
  /// misfires the user's bytes are still recoverable from
  /// `<fileName><CORRUPT_FILE_SUFFIX>`. Only one quarantined copy is kept;
  /// an older one is replaced so repeated failures cannot fill the disk.
  ///
  /// Also removes the `-wal` / `-shm` sidecar files, which belong to the
  /// quarantined database and would otherwise be applied to the new one.
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
    final previous = File(quarantinePath);
    if (previous.existsSync()) {
      await previous.delete();
    }

    for (final suffix in const ['-wal', '-shm']) {
      final sidecar = File('${file.path}$suffix');
      if (sidecar.existsSync()) {
        await sidecar.delete();
      }
    }

    return file.rename(quarantinePath);
  }
}
