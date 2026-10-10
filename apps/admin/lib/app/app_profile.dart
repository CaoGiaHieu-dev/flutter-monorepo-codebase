import 'package:core_common/core_common.dart';

// The `facts` region below is generated from app_manifest.yaml by
//   dart tools/composer/composer.dart sync --app admin
// and checked by `composer verify`: edit the manifest, never the region.

// composer:managed:facts — generated from app_manifest.yaml
const AppFacts appFacts = AppFacts(
  id: 'admin',
  name: 'Codebase Admin',
  flavors: {Flavor.dev, Flavor.staging, Flavor.prod},
  platforms: {
    AppPlatform.web: PlatformFacts(
      // manifest
      runner: RunnerKind.scaffold,
      // derived: capability `splash` is absent
      splash: SplashMode.native,
      // default
      orientation: OrientationPolicy.phonesPortrait,
      // default
      deepLinks: true,
      // derived: core_notifications is not composed
      push: false,
    ),
    AppPlatform.windows: PlatformFacts(
      // manifest
      runner: RunnerKind.scaffold,
      // derived: capability `splash` is absent
      splash: SplashMode.native,
      // default
      orientation: OrientationPolicy.phonesPortrait,
      // default
      deepLinks: true,
      // derived: core_notifications is not composed
      push: false,
    ),
    AppPlatform.macos: PlatformFacts(
      // manifest
      runner: RunnerKind.scaffold,
      // derived: capability `splash` is absent
      splash: SplashMode.native,
      // default
      orientation: OrientationPolicy.phonesPortrait,
      // default
      deepLinks: true,
      // derived: core_notifications is not composed
      push: false,
    ),
    AppPlatform.linux: PlatformFacts(
      // manifest
      runner: RunnerKind.scaffold,
      // derived: capability `splash` is absent
      splash: SplashMode.native,
      // default
      orientation: OrientationPolicy.phonesPortrait,
      // default
      deepLinks: true,
      // derived: core_notifications is not composed
      push: false,
    ),
  },
  env: [
    // manifest
    EnvRule(
      key: 'BASE_URL',
      value: String.fromEnvironment('BASE_URL'),
      requiredIn: {Flavor.prod},
    ),
    // manifest
    EnvRule(
      key: 'APP_NAME',
      value: String.fromEnvironment('APP_NAME'),
    ),
  ],
  capabilities: {
    // manifest (bundle `session`, expanded)
    'session_state': CapabilityExpectation.provided(),
    // manifest (bundle `session`, expanded)
    'session_gateway': CapabilityExpectation.provided(),
    // manifest (bundle `session`, expanded)
    'session_refresh': CapabilityExpectation.provided(),
    // manifest (bundle `session`, expanded)
    'sign_in': CapabilityExpectation.provided(),
    // manifest
    'routes': CapabilityExpectation.provided(),
    // manifest
    'tabs': CapabilityExpectation.provided(),
    // manifest
    'dashboard': CapabilityExpectation.absent(
      'one tab: destinations render without chrome',
    ),
    // manifest
    'entry': CapabilityExpectation.absent(
      'no onboarding: boot goes straight to the sign-in check',
    ),
    // manifest
    'post_sign_in': CapabilityExpectation.absent(
      'no home module: after sign-in the router\'s first tab '
      '(settings) opens',
    ),
    // manifest
    'splash': CapabilityExpectation.absent(
      'native splash is kept through boot',
    ),
    // manifest
    'tree_wrappers': CapabilityExpectation.provided(),
    // manifest
    'localization': CapabilityExpectation.provided(),
    // manifest
    'error_reporter': CapabilityExpectation.absent(
      'no crash backend chosen: errors are printed and sent nowhere '
      '(RULE-67)',
    ),
    // manifest
    'analytics': CapabilityExpectation.absent(
      'no analytics backend chosen: no screen events',
    ),
  },
  sslPinning: SslPinningPolicy({
    // default
    Flavor.dev: SslPinning.disabled(
      'development flavor: local servers use self-signed '
      'certificates',
    ),
    // manifest
    Flavor.staging: SslPinning.disabled(
      'TEMPLATE PLACEHOLDER: no SPKI pins provisioned — '
      'docs/en/guides/08_networking.md § 10',
    ),
    // manifest
    Flavor.prod: SslPinning.disabled(
      'TEMPLATE PLACEHOLDER: no SPKI pins provisioned — '
      'docs/en/guides/08_networking.md § 10',
    ),
  }),
);
// composer:end:facts

/// How the shell behaves for this app — typed, const, template defaults
/// wherever a section is left out. Facts (platforms, flavors, env,
/// capabilities, pins) come from app_manifest.yaml, never from here.
///
/// The sections to tune — each documents its defaults and ranges:
/// `display:` (`DisplayProfile` — the design artboard, the scale policy of
/// each window class, the OS font-size cap), `router:` (`RouterProfile` —
/// the entry-location policy, the fallback location), `locale:`
/// (`LocaleProfile` — the languages offered, the fallback and first-launch
/// language), `theme:` (`ThemeProfile` — the mode a first launch opens in, the
/// palette overrides) and `network:` (`NetworkProfile` — the default HTTP
/// client's timeouts, extra headers and redirect policy).
///
/// This app sets no section, so every value is the template default — the
/// README report (§ 5) prints them. To tune one, pass it by name, for example
/// (a shorter HTTP timeout and a wider text-scale cap):
///
/// ```dart
/// const AppProfile appProfile = AppProfile(
///   facts: appFacts,
///   network: NetworkProfile(connectTimeout: Duration(seconds: 10)),
///   display: DisplayProfile(textScaleMax: 3.0),
/// );
/// ```
///
/// then run `composer sync`: the report's § 5 lists the section as set.
const AppProfile appProfile = AppProfile(facts: appFacts);
