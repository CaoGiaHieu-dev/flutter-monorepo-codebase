// A throwaway workspace for the `composer` tests: one app (`demo`) composing
// one module (`foo`, domain + feature) on top of `core_common`, with every
// generated region present and empty.
//
// The app declares itself the way manifest v2 requires — name, flavors,
// platforms, capabilities — against a catalog of five contracts the fixture
// carries in its own `platform_app_shell/lib/src/utils/
// shell_contract_constants.dart` (composer reads the catalog from the
// workspace, as it reads every package). The pieces are separate so a test can break one.
//
// The declaration is also true of the source: `core_common` registers the one
// required contract, `feature_foo` registers what `session` and `routes` say
// are provided, nothing registers `splash` (declared absent), the entry point
// passes the profile and the smoke test calls `checkAppContract` — so `verify`
// (V3, V12) is green until a test breaks one of them.

/// Repo-relative path of the fixture's catalog source.
const String kFixtureCatalogPath =
    'platform/shell/app_shell/lib/src/utils/shell_contract_constants.dart';

/// The fixture's catalog: one required row, a two-member bundle (`session`),
/// and three more optional rows.
const String kFixtureCatalog = '''
const List<ShellContract<Object>> SHELL_CONTRACTS = [
  ShellContract<ILanguageStorage>(
    id: 'language_storage',
    need: ShellNeed.required,
    cardinality: ContractCardinality.one,
    consumer: 'a/b.dart:1',
    whenAbsent: 'boot throws',
  ),
  ShellContract<ISessionState>(
    id: 'session_state',
    bundle: 'session',
    need: ShellNeed.optional,
    cardinality: ContractCardinality.one,
    consumer: 'a/b.dart:2, a/c.dart:3',
    whenAbsent: 'the app is treated as signed out',
  ),
  ShellContract<ISessionGateway>(
    id: 'session_gateway',
    bundle: 'session',
    need: ShellNeed.optional,
    cardinality: ContractCardinality.one,
    consumer: 'a/b.dart:4',
    whenAbsent:
        'requests carry no bearer token '
        'and nothing refreshes it',
  ),
  ShellContract<IAppSplashScreen>(
    id: 'splash',
    need: ShellNeed.optional,
    cardinality: ContractCardinality.one,
    consumer: 'a/b.dart:5',
    whenAbsent: 'the native splash is kept',
  ),
  ShellContract<IFeatureRouteModule>(
    id: 'routes',
    need: ShellNeed.optional,
    cardinality: ContractCardinality.many,
    consumer: 'a/b.dart:6',
    whenAbsent: 'the router has no stack routes',
  ),
];
''';

/// The default `flavors:` block: `dev` decides nothing (it has a stated
/// default), `staging` and `prod` decide not to pin — the app runs on Android,
/// which can.
const String kFlavors = '''
flavors:
  dev:
  staging:
    ssl_pinning: { disabled: "no SPKI pins provisioned yet" }
  prod:
    ssl_pinning: { disabled: "no SPKI pins provisioned yet" }
''';

/// The default `platforms:` block.
const String kPlatforms = '''
platforms:
  android: { runner: committed }
''';

/// The default `capabilities:` block: every optional row of the fixture
/// catalog declared.
const String kCapabilities = '''
capabilities:
  session: provided
  splash: { state: absent, reason: "the native splash is kept through boot" }
  routes: provided
''';

/// A `demo` manifest. Each declaration block is a parameter so a test replaces
/// one and keeps the rest.
String demoManifest({
  String phase = 'before',
  String modules = '  - { id: foo, layers: [domain, feature] }\n',
  String appBlock = 'app:\n  id: demo\n  name: Demo App\n',
  String flavors = kFlavors,
  String env = '',
  String platforms = kPlatforms,
  String capabilities = kCapabilities,
  String why = '    why: "mechanism only, before anything else"\n',
}) =>
    '$appBlock'
    '$flavors'
    '$env'
    '$platforms'
    '$capabilities'
    'di_groups:\n'
    '  - name: core\n'
    '    phase: $phase\n'
    '    packages: [core_common]\n'
    '$why'
    '  - name: shell\n'
    '    phase: after\n'
    '    packages: [platform_app_shell]\n'
    '    why: "the shell adapters precede what injects them"\n'
    '  - name: domain\n'
    '    phase: after\n'
    '    from_modules: domain\n'
    '    why: "interfaces first: features inject them"\n'
    '  - name: feature\n'
    '    phase: after\n'
    '    from_modules: feature\n'
    '    why: "screens inject the use cases of the groups above"\n'
    'modules:\n'
    '$modules';

/// The entry point of the `demo` app: boots through the shell with its profile.
const String kFixtureMain = '''
import 'package:platform_app_shell/platform_app_shell.dart';

import 'app/app_profile.dart';
import 'di/injection.dart';

void main() => runShellApp(
  profile: appProfile,
  configureDependencies: configureDependencies,
);
''';

/// The `demo` app's DI smoke test: boots a flavor and holds the contract.
const String kFixtureSmokeTest = '''
import 'package:flutter_test/flutter_test.dart';
import 'package:platform_app_shell/platform_app_shell.dart';

import '../lib/app/app_profile.dart';

void main() {
  test('the declared contract holds', () {
    final report = checkAppContract(
      appProfile,
      flavor: Flavor.dev,
      platform: AppPlatform.android,
    );
    expect(report.problems, isEmpty, reason: report.explain());
  });
}
''';

/// What `core_common` registers: the fixture catalog's one required contract.
const String kFixtureCoreRegistrations = '''
import 'package:injectable/injectable.dart';

@Singleton(as: ILanguageStorage)
class LanguageStorageImpl implements ILanguageStorage {}
''';

/// What `feature_foo` registers: both members of the `session` bundle (through
/// a module, as `feature_auth` does) and the `routes` contract.
const String kFixtureFeatureRegistrations = '''
import 'package:injectable/injectable.dart';

@module
abstract class FooSessionModule {
  @lazySingleton
  ISessionState bindState(FooSession session) => session;

  @lazySingleton
  ISessionGateway bindGateway(FooSession session) => session;
}

@LazySingleton(as: IFeatureRouteModule)
class FooRoutes implements IFeatureRouteModule {}
''';

/// A splash screen `feature_foo` can register, for a test whose app declares
/// `splash: provided`.
const String kFixtureSplashRegistration = '''
import 'package:injectable/injectable.dart';

@LazySingleton(as: IAppSplashScreen)
class FooSplash implements IAppSplashScreen {}
''';

/// The app's own per-flavor `FirebaseOptions`, what `core_notifications` asks
/// an app that composes it to register (V10).
const String kFixtureFirebaseModule = '''
import 'package:injectable/injectable.dart';

@module
abstract class FirebaseModule {
  @lazySingleton
  @Environment('dev')
  FirebaseOptions get dev => throw UnimplementedError();

  @lazySingleton
  @Environment('staging')
  FirebaseOptions get staging => throw UnimplementedError();

  @lazySingleton
  @Environment('prod')
  FirebaseOptions get prod => throw UnimplementedError();
}
''';

/// A package's DI module — what makes `composer` import it in `injection.dart`.
String diModule() =>
    "import 'package:injectable/injectable.dart';\n\n"
    '@InjectableInit.microPackage()\n'
    'void initMicroPackage() {}\n';

/// The files of the `demo` workspace. [manifest] replaces the default,
/// [extra] adds or overwrites files (a `null` value is not allowed — remove
/// what you do not want from the returned map instead).
Map<String, String> demoWorkspaceFiles({
  String? manifest,
  Map<String, String> extra = const {},
}) => {
  'pubspec.yaml':
      'name: ws\n'
      'workspace:\n'
      '  # composer:managed:workspace — generated from app_manifest.yaml\n'
      '  # composer:end:workspace\n',
  'apps/demo/app_manifest.yaml': manifest ?? demoManifest(),
  'apps/demo/pubspec.yaml':
      'name: demo_app\n'
      'resolution: workspace\n'
      'dependencies:\n'
      '  # composer:managed:deps — generated from app_manifest.yaml\n'
      '  # composer:end:deps\n',
  'apps/demo/lib/di/injection.dart':
      '// composer:managed:imports — generated from app_manifest.yaml\n'
      '// composer:end:imports\n'
      '\n'
      '// composer:managed:modules — generated from app_manifest.yaml\n'
      '// composer:end:modules\n',
  'apps/demo/lib/app/app_profile.dart':
      "import 'package:core_common/core_common.dart';\n"
      '\n'
      '// composer:managed:facts — generated from app_manifest.yaml\n'
      '// composer:end:facts\n'
      '\n'
      'const AppProfile appProfile = AppProfile(facts: appFacts);\n',
  'apps/demo/README.md':
      '# demo\n'
      '\n'
      '<!-- composer:managed:report — generated from app_manifest.yaml -->\n'
      '<!-- composer:end:report -->\n',
  'apps/demo/lib/main.dart': kFixtureMain,
  'apps/demo/test/di_smoke_test.dart': kFixtureSmokeTest,
  // `runner: committed` for android needs the folder.
  'apps/demo/android/README.txt': 'runner\n',
  'platform/foundation/common/pubspec.yaml': 'name: core_common\n',
  'platform/foundation/common/lib/di/module.dart': diModule(),
  'platform/foundation/common/lib/src/language_storage.dart':
      kFixtureCoreRegistrations,
  'platform/shell/app_shell/pubspec.yaml': 'name: platform_app_shell\n',
  kFixtureCatalogPath: kFixtureCatalog,
  'modules/foo/domain/pubspec.yaml': 'name: domain_foo\n',
  'modules/foo/domain/lib/di/module.dart': diModule(),
  'modules/foo/feature/pubspec.yaml':
      'name: feature_foo\n'
      'dependencies:\n'
      '  domain_foo:\n'
      '    path: ../domain\n',
  'modules/foo/feature/lib/di/module.dart': diModule(),
  'modules/foo/feature/lib/src/registrations.dart':
      kFixtureFeatureRegistrations,
  ...extra,
};
