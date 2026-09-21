/// SAMPLE CODE — safe to delete.
///
/// This package is a reference implementation shipped with the template,
/// not product code. It demonstrates:
/// a Retrofit data source, Freezed models with `.toEntity()`, a package-owned
/// storage key, and a repository that wraps both in `execute()` so nothing
/// throws past this layer.
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
