/// SAMPLE CODE — safe to delete.
///
/// This package is a reference implementation shipped with the template,
/// not product code. It demonstrates:
/// Shell chrome only — builds the bottom bar from whatever tabs register
/// themselves. Owns no business logic and no tab page.
///
/// To remove it and everything that travels with it:
///
/// ```sh
/// dart tools/sample_cleanup/remove_sample.dart dashboard            # preview
/// dart tools/sample_cleanup/remove_sample.dart dashboard --apply    # do it
/// ```
///
/// Classification and the full removal bundle live in
/// `tools/sample_manifest.yaml`.
library;

// Auto-generated exports, do not edit manually.
export 'di/module.dart';
export 'di/module.module.dart';
export 'src/pages/dashboard_page.dart';
export 'src/routing/dashboard_route_module_impl.dart';
