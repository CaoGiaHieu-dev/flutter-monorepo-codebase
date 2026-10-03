import 'package:core_common/core_common.dart';

// The `facts` region below is generated from app_manifest.yaml by
//   dart tools/composer/composer.dart sync --app mobile
// and checked by `composer verify`: edit the manifest, never the region.

// composer:managed:facts — generated from app_manifest.yaml
const AppFacts appFacts = AppFacts(
  id: 'mobile',
  name: 'Codebase',
  flavors: {Flavor.dev, Flavor.staging, Flavor.prod},
  platforms: {
    AppPlatform.android: PlatformFacts(
      // manifest
      runner: RunnerKind.committed,
      // derived: capability `splash` is provided
      splash: SplashMode.dart,
      // default
      orientation: OrientationPolicy.phonesPortrait,
      // default
      deepLinks: true,
      // derived: core_notifications is composed and supports android
      push: true,
    ),
    AppPlatform.ios: PlatformFacts(
      // manifest
      runner: RunnerKind.committed,
      // default: iOS keeps its native splash for the whole boot
      splash: SplashMode.native,
      // default
      orientation: OrientationPolicy.phonesPortrait,
      // default
      deepLinks: true,
      // derived: core_notifications is composed and supports ios
      push: true,
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
      requiredIn: {Flavor.staging, Flavor.prod},
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
    'dashboard': CapabilityExpectation.provided(),
    // manifest
    'entry': CapabilityExpectation.provided(),
    // manifest
    'post_sign_in': CapabilityExpectation.provided(),
    // manifest
    'splash': CapabilityExpectation.provided(),
    // manifest
    'tree_wrappers': CapabilityExpectation.provided(),
    // manifest
    'localization': CapabilityExpectation.provided(),
    // manifest
    'error_reporter': CapabilityExpectation.absent(
      'no crash backend chosen: errors are printed and sent nowhere '
      '— implement IErrorReporter in lib/app/, then declare it '
      'provided (RULE-67)',
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
const AppProfile appProfile = AppProfile(facts: appFacts);
