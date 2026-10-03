import 'package:get_it/get_it.dart';

import '../service_locator.dart';
import '../utils/profile_constants.dart';
import 'app_platform.dart';
import 'app_profile.dart';
import 'locale_profile.dart';
import 'network_profile.dart';
import 'platform_facts.dart';
import 'router_profile.dart';
import 'ssl_pinning.dart';
import 'theme_profile.dart';

/// Registers [profile], and each section a consumer reads, under its own exact
/// type.
///
/// GetIt resolves the exact registered type, never a supertype (RULE-14), so
/// each section is bound in its own right: [AppProfile], [AppPlatform] and
/// [PlatformFacts] — the platform this run is on and its declared facts —
/// [SslPinningPolicy], [RouterProfile], [LocaleProfile], [ThemeProfile] and
/// [NetworkProfile]. A DI-built class then takes the
/// section it needs as a constructor parameter, optional with a `const`
/// default. (`DisplayProfile` is not registered: `MainScope` and
/// `AppMaterialWrapper` are not DI-built, and `runShellApp` hands each its
/// section.)
///
/// `runShellApp` calls this *before* the generated `configureDependencies`:
/// an eager singleton built while the graph initialises can inject a section,
/// and nothing registered later can shadow it. A harness that boots
/// `configureDependencies` without `runShellApp` (an app's DI smoke test)
/// calls it itself, which is what makes the test hold the same profile
/// production does.
///
/// Idempotent: registering the same [profile] again changes nothing, and a
/// different one replaces the previous registration, so a test can register
/// per case without resetting the locator in between.
///
/// Throws [StateError] when [platform] is not declared in the profile, unless
/// [allowUndeclaredPlatform] is true — it defaults to the
/// `ALLOW_UNDECLARED_PLATFORM` define (`ProfileConstants`). The undeclared
/// platform then gets `PlatformFacts.today()`, so a quick look on an unlisted
/// platform behaves as the app did before it could declare one.
/// `runShellApp` has already stopped the boot with `P01` by the time it gets
/// here; a test passes a declared platform.
///
/// Registers into [locator] when given, else the global [getIt].
void registerAppProfile(
  AppProfile profile, {
  required AppPlatform platform,
  GetIt? locator,
  bool? allowUndeclaredPlatform,
}) {
  final declared = profile.facts.platformFor(platform);
  final allowed =
      allowUndeclaredPlatform ?? ProfileConstants.ALLOW_UNDECLARED_PLATFORM;
  if (declared == null && !allowed) {
    throw StateError(
      '${profile.facts.id} does not declare the platform ${platform.name}. '
      'Add it under `platforms:` in apps/${profile.facts.id}/app_manifest.yaml '
      'and run `dart tools/composer/composer.dart sync --app '
      '${profile.facts.id}`.',
    );
  }

  final target = locator ?? getIt;
  _register<AppProfile>(target, profile);
  _register<AppPlatform>(target, platform);
  _register<PlatformFacts>(target, declared ?? const PlatformFacts.today());
  _register<SslPinningPolicy>(target, profile.facts.sslPinning);
  _register<RouterProfile>(target, profile.router);
  _register<LocaleProfile>(target, profile.locale);
  _register<ThemeProfile>(target, profile.theme);
  _register<NetworkProfile>(target, profile.network);
}

/// Binds [instance] under exactly `T`, replacing an earlier different one.
void _register<T extends Object>(GetIt locator, T instance) {
  if (locator.isRegistered<T>()) {
    if (identical(locator.get<T>(), instance)) return;
    locator.unregister<T>();
  }
  locator.registerSingleton<T>(instance);
}
