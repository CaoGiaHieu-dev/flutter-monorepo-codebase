/// SAMPLE CODE — safe to delete.
///
/// This package is a reference implementation shipped with the template,
/// not product code. It demonstrates:
/// A stack route (`IFeatureRouteModule`) and the cold-start entry point
/// (`IAppEntryLocation`).
///
/// To remove it and everything that travels with it:
///
/// ```sh
/// dart tools/sample_cleanup/remove_sample.dart onboarding            # preview
/// dart tools/sample_cleanup/remove_sample.dart onboarding --apply    # do it
/// ```
///
/// Classification and the full removal bundle live in
/// `tools/sample_manifest.yaml`.
library;

// Auto-generated exports, do not edit manually.
export 'di/localization.dart';
export 'di/module.dart';
export 'di/module.module.dart';
export 'src/extensions/l10n_onboarding_extension.dart';
export 'src/gen/language/app_localizations.dart';
export 'src/gen/language/app_localizations_en.dart';
export 'src/gen/language/app_localizations_vi.dart';
export 'src/pages/onboarding_page.dart';
export 'src/routing/onboarding_app_entry_location.dart';
export 'src/routing/onboarding_feature_route_module.dart';
export 'src/routing/onboarding_route_module.dart';
export 'src/utils/onboarding_path.dart';
