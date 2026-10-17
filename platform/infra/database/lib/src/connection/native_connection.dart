import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart' show Database;

import '../utils/database_constants.dart';

// The native side of `DatabaseConnectionFactory` (Android, iOS, macOS,
// Windows, Linux): a SQLite file opened on background drift isolates. The
// factory reaches it through a configurable import — the default target, so
// `dart:ffi` never reaches a web build.

/// Opens [fileName]'s executor on a background isolate.
Future<QueryExecutor> openExecutor(
  String fileName, {
  required int readPool,
}) async {
  final file = await resolveDatabaseFile(fileName);
  return backgroundExecutorFor(file, readPool: readPool);
}

/// The database file [fileName] in the app's private directory.
Future<File> resolveDatabaseFile(String fileName) async {
  // Where an app's private files live is an OS convention: Android and iOS
  // keep the documents directory every shipped install already uses; on
  // Windows and Linux "documents" is the user's shared ~/Documents, so the
  // desktop uses the per-application support directory.
  final directory = switch (defaultTargetPlatform) {
    TargetPlatform.android ||
    TargetPlatform.iOS ||
    TargetPlatform.fuchsia => await getApplicationDocumentsDirectory(),
    TargetPlatform.linux ||
    TargetPlatform.windows ||
    TargetPlatform.macOS => await getApplicationSupportDirectory(),
  };
  return File(p.join(directory.path, fileName));
}

/// [openExecutor] for an explicit [file] — the part that does not need the
/// path_provider plugin, so a unit test can open a real file.
///
/// Uses [NativeDatabase.createInBackground] so all synchronous sqlite3 I/O
/// runs off the UI thread without manual [DriftIsolate] boilerplate. With
/// [readPool] above zero drift opens one more connection per reader, each on
/// its own isolate. `MigrationStrategy.beforeOpen` runs on the writer only,
/// so a per-connection `PRAGMA` set there never reaches the readers;
/// [_configureConnection] runs on every connection instead.
QueryExecutor backgroundExecutorFor(
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
/// Sent to each drift isolate, so it must stay a top-level function that
/// captures nothing. Without `busy_timeout` a reader meeting a lock — a WAL
/// checkpoint, a recovery — fails at once with `SQLITE_BUSY` instead of
/// waiting. The writer gets the same value again in `beforeOpen`, which is
/// also where a database's own `busyTimeoutMs` override applies.
void _configureConnection(Database database) {
  database.execute(
    'PRAGMA busy_timeout = ${DatabaseConstants.BUSY_TIMEOUT_MS}',
  );
}

/// Moves the unreadable database file [fileName] aside so a fresh one can be
/// created.
///
/// The file is **renamed, never deleted** — if the corruption check ever
/// misfires the user's bytes are still recoverable from
/// `<fileName><CORRUPT_FILE_SUFFIX>`. Only one quarantined copy is kept; an
/// older one is replaced so repeated failures cannot fill the disk.
///
/// The `-wal` / `-shm` sidecars move with it (`<fileName>.corrupt-wal`,
/// `.corrupt-shm`): they belong to the quarantined database and must not be
/// applied to the new one, and the WAL holds committed transactions not yet
/// checkpointed — deleting it would lose exactly the newest data the
/// quarantine exists to keep recoverable.
///
/// Returns `true` when the file was moved, `false` when there was nothing to
/// move (the database had not been created yet).
Future<bool> quarantine(String fileName) async {
  final file = await resolveDatabaseFile(fileName);
  if (!file.existsSync()) return false;

  final quarantinePath = '${file.path}${DatabaseConstants.CORRUPT_FILE_SUFFIX}';
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

  await file.rename(quarantinePath);
  return true;
}
