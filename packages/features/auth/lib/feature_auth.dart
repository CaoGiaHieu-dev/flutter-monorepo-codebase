/// SAMPLE CODE — safe to delete.
///
/// This package is a reference implementation shipped with the template,
/// not product code. It demonstrates:
/// Provider state management, a global `@lazySingleton` controller, Firebase
/// auth through the data layer, and the cross-feature contracts
/// (`IAuthStatusStream`, `IAuthActionHandler`) other samples consume.
///
/// To remove it and everything that travels with it:
///
/// ```sh
/// dart tools/sample_cleanup/remove_sample.dart auth            # preview
/// dart tools/sample_cleanup/remove_sample.dart auth --apply    # do it
/// ```
///
/// Classification and the full removal bundle live in
/// `tools/sample_manifest.yaml`.
library;

// Auto-generated exports, do not edit manually.
export 'di/di.dart';
export 'src/src.dart';
