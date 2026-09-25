/// SAMPLE CODE — safe to delete.
///
/// This package is a reference implementation shipped with the template,
/// not product code. It demonstrates:
/// a package-owned Drift database — table, DAO, migrations through
/// `core_database` — behind a local data source, a model that keeps Drift's
/// generated row type out of the public API, and a repository.
///
/// To remove it and everything that travels with it:
///
/// ```sh
/// dart tools/sample_cleanup/remove_sample.dart cache            # preview
/// dart tools/sample_cleanup/remove_sample.dart cache --apply    # do it
/// ```
///
/// Classification and the full removal bundle live in
/// `tools/sample_manifest.yaml`.
library;

// Auto-generated exports, do not edit manually.
export 'di/module.dart';
export 'di/module.module.dart';
export 'src/data_sources/local/cache_entry_local_data_source.dart';
export 'src/database/cache_database.dart';
export 'src/database/tables/cache_entries_table.dart';
export 'src/models/cache_entry_model.dart';
export 'src/repositories_impl/cache_entry_repository_impl.dart';
export 'src/utils/cache_constants.dart';
