import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';
import 'package:dynamic_logger/dynamic_logger.dart';

// The web side of `DatabaseConnectionFactory`: drift's wasm build of SQLite,
// in a worker, stored in OPFS or IndexedDB — whichever the browser offers.
// The factory reaches it through a configurable import
// (`if (dart.library.js_interop)`), so neither `dart:io` nor `path_provider`
// is imported here.

/// Opens [fileName] in drift's wasm worker.
///
/// Needs `sqlite3.wasm` and `drift_worker.js` next to the app's `index.html`
/// (`composer runners` writes both into a generated web runner). The URIs are
/// relative, so the browser resolves them against `<base href>` and an app
/// served under a sub-path still finds them. [readPool] is ignored: one
/// worker owns the connection.
Future<QueryExecutor> openExecutor(
  String fileName, {
  required int readPool,
}) async {
  final result = await WasmDatabase.open(
    databaseName: fileName,
    sqlite3Uri: Uri.parse('sqlite3.wasm'),
    driftWorkerUri: Uri.parse('drift_worker.js'),
  );
  DynamicLogger.log(
    'Web database "$fileName": ${result.chosenImplementation}'
    '${result.missingFeatures.isEmpty ? '' : ' (missing browser features: '
              '${result.missingFeatures.join(', ')})'}',
    tag: 'core_database',
    level: LogLevel.INFO,
  );
  return result.resolvedExecutor;
}

/// Always `false`: on the web a database is not a file that can be moved
/// aside.
Future<bool> quarantine(String fileName) async => false;
