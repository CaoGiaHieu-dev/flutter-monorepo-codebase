import '../service_locator.dart';
import 'app_platform.dart';
import 'app_profile.dart';

/// Where the platform switch [name] (`push`, `deep_links`) is written, for the
/// log line that says a feature is off: `platforms.windows.push in
/// apps/admin/app_manifest.yaml`.
///
/// A feature a platform does not enable never goes quiet — it says once which
/// manifest key turned it off. The platform and the app come from what
/// `registerAppProfile` registered; without them (a class built by hand in a
/// test) the text names the key generically.
String platformSwitchKey(String name) {
  final platform = getItOrNull<AppPlatform>();
  final profile = getItOrNull<AppProfile>();
  final key = 'platforms.${platform?.name ?? '<platform>'}.$name';
  final manifest = profile == null
      ? 'the app manifest'
      : 'apps/${profile.facts.id}/app_manifest.yaml';
  return '$key in $manifest';
}
