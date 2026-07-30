import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Factory for opening SQLite connections on a background Drift isolate.
///
/// Uses [NativeDatabase.createInBackground] so all synchronous sqlite3 I/O
/// runs off the UI thread without manual [DriftIsolate] boilerplate.
abstract final class DatabaseConnectionFactory {
  static const String defaultFileName = 'app_database.sqlite';

  /// Resolves the on-disk database file path inside app documents.
  static Future<File> resolveDatabaseFile({
    String fileName = defaultFileName,
  }) async {
    final directory = await getApplicationDocumentsDirectory();
    return File(p.join(directory.path, fileName));
  }

  /// Creates a [QueryExecutor] backed by a background isolate.
  static Future<QueryExecutor> createBackgroundExecutor({
    String fileName = defaultFileName,
    int readPool = 1,
  }) async {
    final file = await resolveDatabaseFile(fileName: fileName);
    return NativeDatabase.createInBackground(file, readPool: readPool);
  }
}
