import 'package:drift/drift.dart';

import 'connection/native_connection.dart'
    if (dart.library.js_interop) 'connection/web_connection.dart'
    as connection;
import 'utils/database_constants.dart';

/// Opens SQLite connections: on a background isolate natively, in drift's
/// wasm worker on the web (a configurable import — the compiler picks).
abstract final class DatabaseConnectionFactory {
  /// The executor of the package-owned database [fileName].
  ///
  /// Natively the file lives in the app's private directory — the documents
  /// directory on Android and iOS, the application-support directory on the
  /// desktop — and [readPool] read-only connections open next to the writer,
  /// each on its own isolate. On the web it is drift's wasm SQLite in a
  /// worker, which owns the one connection.
  static Future<QueryExecutor> createBackgroundExecutor({
    required String fileName,
    int readPool = DatabaseConstants.DEFAULT_READ_POOL,
  }) => connection.openExecutor(fileName, readPool: readPool);

  /// Moves a corrupt database aside; `false` when there was nothing to move,
  /// and always on the web, where a database is not a file.
  ///
  /// The file is renamed, never deleted, together with its `-wal` / `-shm`
  /// sidecars, to `<fileName><CORRUPT_FILE_SUFFIX>`.
  static Future<bool> quarantineDatabaseFile({required String fileName}) =>
      connection.quarantine(fileName);
}
