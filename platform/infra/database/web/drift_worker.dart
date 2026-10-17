import 'package:drift/wasm.dart';

/// Drift's web worker, which owns every wasm database of an app on the web.
///
/// Compiled to `drift_worker.js` in a generated web runner's `web/` by
/// `dart tools/composer/composer.dart runners`, for an app that links
/// `core_database`. Outside `lib/`, so the package barrel never exports it.
void main() => WasmDatabase.workerMainForOpen();
