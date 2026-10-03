import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../composer/src/catalog.dart';
import '../shared/contract_scan.dart';
import '../unused_checker/monorepo_helper.dart';
import '../unused_checker/output_formatter.dart';
import 'dart_source.dart';
import 'platform_forks.dart';
import 'source_rules.dart';

/// Mechanical enforcement of the architecture rules in the rule registry,
/// `docs/en/reference/01_rules.md` (RULE-NN ids).
///
/// A rule nobody can break by accident is a rule; a rule you have to remember
/// is a suggestion. Every check here maps to a numbered rule and prints
/// `file:line` so a violation is one click away.
///
/// Exit code 0 = clean, 1 = at least one blocking violation.

// ---------------------------------------------------------------------------
// Approved exceptions — the ONLY upward edges allowed out of `core/*`.
// Printed on every run so they stay visible instead of rotting in a comment.
// Adding one here without updating the registry (RULE-01) is itself a violation.
// ---------------------------------------------------------------------------
const _approvedUpwardEdges = <String, String>{
  'provider_state_management -> domain_core':
      'Needs Result<T> and AppFailure for executeOperation / '
      'OperationConfig.',
  'platform_kernel -> domain_core':
      'ErrorHandler produces AppFailure, which lives in domain_core. '
      'Core -> Domain is the correct Clean Architecture direction.',
  'bloc_state_management -> domain_core':
      'BlocViewState.error carries AppFailure directly.',
  'data_core -> domain_core':
      'BaseRepository returns Result<T> and AppFailure, which live in '
      'domain_core. Data -> Domain is the correct Clean Architecture '
      'direction, and both packages are platform layers.',
};

/// The one file in an app that is allowed to name the modules it composes,
/// relative to the app: the composition root `composer sync` generates.
///
/// Compared as an exact path — a file merely *named* `injection.dart` somewhere
/// else under `lib/` is not the root. Injectable generates
/// `injection.config.dart` beside it, which [isGeneratedSource] skips.
const _compositionRoot = 'lib/di/injection.dart';

/// Where each workspace package sits, by package name: its [_layerOf] and its
/// [_moduleOf]. Filled in by [main] before any rule runs.
///
/// Every classification of an edge's *target* goes through these — never
/// through the target's name. A hosted package called `feature_discovery` or
/// `data_table_2` is not one of ours, and a workspace package named wrongly is
/// still judged by the folder it lives in.
final Map<String, String> _layers = <String, String>{};
final Map<String, String?> _modules = <String, String?>{};

/// The layers that live under `modules/` — the module side of the ring.
const _moduleLayers = {'domain', 'data', 'features', 'api', 'module'};

/// Whether [packageName] is a workspace package that lives under `modules/`
/// (a module's domain, data, feature, API or custom package) — R10's "a
/// package an app must not import". `domain_core` and `data_core` are layer
/// foundations under `platform/` that every app may depend on directly; a
/// hosted package, whatever its name, is not a module package.
bool _isModulePackage(String packageName) =>
    _moduleLayers.contains(_layers[packageName]);

/// Every module API package in the workspace: the package in `modules/<m>/api`.
///
/// By location, because the suffix alone is not a reliable signal for an
/// import target — pub.dev is full of `*_api` packages — while a workspace
/// package under `modules/<m>/api` is one of ours. Filled in by [main] before
/// any rule runs.
final Set<String> _apiPackages = <String>{};

/// The platform groups, by folder: `platform/<group>/<package>`.
const _platformGroups = {
  'foundation',
  'layers',
  'infra',
  'ui',
  'state',
  'shell',
};

/// R11: which groups each platform group may depend on (`dependencies:`).
///
/// `layers` is split by folder because its two members sit at opposite ends
/// of the DAG: `layers/domain` (`domain_core`) is the leaf everything may
/// reach, `layers/data` (`data_core`, and any other `platform/layers/*`)
/// builds on the foundation. `shell` composes everything, so it may reach
/// every group; nothing else may reach `shell`.
const _allowedGroupEdges = <String, Set<String>>{
  'layers/domain': {},
  'foundation': {'foundation', 'layers/domain'},
  'layers': {'foundation', 'layers/domain'},
  'infra': {'foundation', 'layers/domain', 'layers'},
  'ui': {'foundation', 'ui'},
  'state': {'foundation', 'layers/domain', 'layers', 'ui'},
  'shell': {
    'foundation',
    'layers/domain',
    'layers',
    'infra',
    'ui',
    'state',
    'shell',
  },
};

/// The R11 group of a package under `platform/`, derived from its **path**:
/// `platform/<group>/<package>` → `<group>`, with `platform/layers/domain`
/// reported as `layers/domain`. Returns null outside `platform/`, and
/// `invalid` for a package not sitting exactly one folder deep in a known
/// group — R11 reports that as well, so a package cannot opt out of the
/// direction check by living somewhere unexpected.
///
/// The one rule that reads the path rather than the name: the group is
/// recorded *only* by the folder (package names never mention it).
String? _platformGroupOf(MonorepoPackage pkg, String root) {
  final rel = p.posix.relative(pkg.rootPath, from: root);
  final segments = p.posix.split(rel);
  if (segments.isEmpty || segments.first != 'platform') return null;
  if (segments.length != 3 || !_platformGroups.contains(segments[1])) {
    return 'invalid';
  }
  if (segments[1] == 'layers') {
    return segments[2] == 'domain' ? 'layers/domain' : 'layers';
  }
  return segments[1];
}

/// Transport and persistence libraries: a layer that must stay free of them
/// (the domain, the kernel) may not declare or import any.
const _transportPackages = <String>{
  'dio',
  'retrofit',
  'drift',
  'go_router',
  'http',
};

/// Anything that drags a Flutter binding in, by name. A package not listed
/// here is still caught when its own dependencies reach Flutter
/// ([_FlutterClosure]).
const _flutterBound = <String>{
  'flutter',
  'flutter_test',
  'flutter_driver',
  'integration_test',
  'flutter_localizations',
  'flutter_web_plugins',
  'material_ui',
  'cupertino_ui',
  'go_router',
  'provider',
  'flutter_bloc',
};

/// `dart:` libraries that exist only on the Flutter engine or in a browser, so
/// a pure-Dart package (the domain, the kernel) that imports one cannot run on
/// a Dart VM. `dart:io` is deliberately not here: the kernel and the data
/// layer use it, and whether a domain may is not decided.
const _engineOnlyDartLibraries = <String>{
  'ui',
  'html',
  'js',
  'js_interop',
  'js_interop_unsafe',
  'js_util',
  'web_ui',
  'web_gl',
  'web_audio',
  'web_sql',
  'indexed_db',
  'svg',
};

/// Why a pure-Dart package may not import `dart:<library>`, or null when it
/// may.
String? _dartLibraryProblem(String? library) =>
    library != null && _engineOnlyDartLibraries.contains(library)
    ? 'a Flutter-engine or browser-only Dart library'
    : null;

/// Why a pure-Dart package (the domain, the kernel) may not use [dep] — null
/// when it may. [flutter] is asked about packages that are not named in
/// [_flutterBound] or [_transportPackages]: a Flutter plugin, or a package
/// that depends on the Flutter SDK, is as unusable on a Dart VM as the SDK.
String? _pureDartProblem(String dep, _FlutterClosure flutter) {
  if (_transportPackages.contains(dep)) {
    return 'a transport or persistence package';
  }
  if (_flutterBound.contains(dep)) return 'Flutter or a Flutter-bound package';
  final culprit = flutter.culprit(dep);
  if (culprit != null) {
    return culprit == dep
        ? 'a Flutter plugin'
        : 'it depends on the Flutter-bound `$culprit`';
  }
  return null;
}

/// Why a domain package ([pkg]: `modules/<m>/domain`, or `domain_core`) may
/// not depend on [dep] — null when it may. RULE-03: pure Dart, no transport,
/// and no workspace package outside the domain layer. The only workspace edges
/// a domain may have are `domain_core` and a `domain_*` of its **own** module:
/// another module's domain (or API) would chain that module's removal to this
/// one, and the platform and the outer rings are refused outright.
///
/// Judged by where [dep] lives in the workspace, never by its name: a hosted
/// package called `core_extension` is a pub.dev package like any other, and
/// goes through the transport / Flutter lists.
String? _domainDependencyProblem(
  MonorepoPackage pkg,
  String dep,
  Map<String, MonorepoPackage> packages,
  String root,
  _FlutterClosure flutter,
) {
  if (dep == pkg.name) return null;
  final target = packages[dep];
  if (target == null) return _pureDartProblem(dep, flutter);
  final layer = _layers[dep];
  switch (layer) {
    case 'domain':
      final same = _modules[dep] != null && _modules[dep] == _modules[pkg.name];
      if (!same) return 'another module\'s domain package';
    case 'core':
      if (_platformGroupOf(target, root) != 'layers/domain') {
        return 'a platform package';
      }
    case 'api':
      return 'a module API package';
    case 'data' || 'features' || 'module':
      return 'a module package outside the domain layer';
    case 'app':
      return 'an app';
    default:
      return 'a workspace package outside the domain layer';
  }
  return _pureDartProblem(dep, flutter);
}

/// The pure-Dart tier: packages that must run on a Dart VM, with no Flutter
/// binding anywhere in their dependency closure.
///
/// `platform_kernel` is the foundation every other package may depend on, so
/// its dependency list becomes everyone's — the reason it is held to a harder
/// line than `core_*`.
///
/// `modules/*/domain` and `domain_core` are covered by R2 instead, which holds
/// them to the same transport and Flutter lists.
bool _isPureDartTier(String packageName) => packageName == 'platform_kernel';

/// Which packages drag Flutter in, by what they declare rather than by name.
///
/// A package is Flutter-bound when it depends on the Flutter SDK
/// (`flutter: sdk: flutter`, `flutter_localizations`, …) or is a Flutter
/// plugin (a top-level `flutter: plugin:` section), or when any package it
/// depends on is. Workspace packages are read from their own pubspec; hosted
/// ones from `.dart_tool/package_config.json`, which `pub get` writes. Without
/// that file only the workspace and the named lists are known — the gate runs
/// after `pub get` in CI, where the file is always there.
class _FlutterClosure {
  _FlutterClosure(String root, this._workspace)
    : _hosted = _readPackageConfig(root);

  final Map<String, MonorepoPackage> _workspace;
  final Map<String, String> _hosted;
  final Map<String, String?> _memo = {};

  /// Package name -> the directory pub resolved it to.
  static Map<String, String> _readPackageConfig(String root) {
    final file = File(p.join(root, '.dart_tool', 'package_config.json'));
    if (!file.existsSync()) return const {};
    try {
      final json = jsonDecode(file.readAsStringSync());
      final out = <String, String>{};
      for (final entry in (json as Map)['packages'] as List) {
        final name = (entry as Map)['name'] as String;
        final dir = file.uri.resolve('${entry['rootUri']}/');
        out[name] = p.posix.normalize(dir.toFilePath().replaceAll(r'\', '/'));
      }
      return out;
    } on Object {
      return const {};
    }
  }

  YamlMap? _pubspecOf(String name) {
    final member = _workspace[name];
    if (member != null) return member.pubspec;
    final dir = _hosted[name];
    if (dir == null) return null;
    final file = File(p.join(dir, 'pubspec.yaml'));
    if (!file.existsSync()) return null;
    try {
      final yaml = loadYaml(file.readAsStringSync());
      return yaml is YamlMap ? yaml : null;
    } on YamlException {
      return null;
    }
  }

  /// The Flutter-bound package reached from [name] (itself included), or null.
  String? culprit(String name) {
    if (_memo.containsKey(name)) return _memo[name];
    _memo[name] = null; // a dependency cycle ends here
    return _memo[name] = _resolve(name);
  }

  String? _resolve(String name) {
    if (_flutterBound.contains(name)) return name;
    final yaml = _pubspecOf(name);
    if (yaml == null) return null;
    final flutterSection = yaml['flutter'];
    if (flutterSection is YamlMap && flutterSection.containsKey('plugin')) {
      return name;
    }
    final deps = yaml['dependencies'];
    if (deps is! YamlMap) return null;
    for (final entry in deps.entries) {
      final dep = entry.key;
      if (dep is! String) continue;
      final spec = entry.value;
      if (spec is YamlMap && spec['sdk'] == 'flutter') return dep;
      final found = culprit(dep);
      if (found != null) return found;
    }
    return null;
  }
}

/// Packages every Dart package may import without declaring: they ship with
/// the SDK rather than through `pubspec.yaml` resolution.
const _sdkPackages = <String>{
  'flutter',
  'flutter_test',
  'flutter_localizations',
  'flutter_web_plugins',
  'flutter_driver',
  'integration_test',
};

class Violation {
  Violation(this.rule, this.location, this.message);

  /// Rule id, e.g. `R1`.
  final String rule;

  /// `path:line`, or just `path` when the whole file is the subject.
  final String location;
  final String message;
}

/// Public `static const` declaration (i.e. not `_privateName`).
final _publicStaticConst = RegExp(
  r'''^\s*static\s+const\s+(?:[\w<>,\s\?]+\s+)?([A-Za-z]\w*)\s*=''',
  multiLine: true,
);

/// How one package reaches another (or a `dart:` library).
enum _UseKind {
  /// An `import` / `export` in lib/.
  import('imports', ships: true, isImport: true),

  /// A `dependencies:` entry.
  declared('declares', ships: true, isImport: false),

  /// A `dev_dependencies:` entry.
  dev('declares under `dev_dependencies:`', ships: false, isImport: false),

  /// An `import` / `export` in test/ or integration_test/.
  testImport('imports from a test', ships: false, isImport: true);

  const _UseKind(this.verb, {required this.ships, required this.isImport});

  /// What the violation says the package does.
  final String verb;

  /// Whether it reaches a consumer (lib/ and `dependencies:`), as opposed to a
  /// test or a dev dependency.
  final bool ships;
  final bool isImport;
}

/// One edge out of a package: to a `package:` target, or to a `dart:` library.
class _Use {
  const _Use(this.package, this.dartLibrary, this.location, this.kind);

  /// The package it reaches, or null for a `dart:` import.
  final String? package;

  /// The `dart:` library (`ui`), or null for a package.
  final String? dartLibrary;

  /// `path:line`, or the pubspec for a declared dependency.
  final String location;
  final _UseKind kind;
}

/// Every file is lexed once and kept: R1–R10 each read the same directives.
final Map<String, DartSource> _scanCache = <String, DartSource>{};

DartSource _scanFile(String file) => _scanCache.putIfAbsent(
  file,
  () => DartSource.scan(File(file).readAsStringSync()),
);

/// The architectural layer a package belongs to, derived from its **folder**.
///
/// - an app: recognised by the marker `composer` uses — an `app_manifest.yaml`
///   beside its pubspec — because app packages are named for the product
///   (`app`, `admin_app`), not for a layer;
/// - anything under `platform/` (or stray, directly under it) is `core`,
///   whatever its name: `data_core` and `domain_core` carry a layer prefix but
///   are platform packages;
/// - `modules/<module>/{domain,data,feature,api}` is `domain`, `data`,
///   `features`, `api`; any other folder under `modules/` is `module` (a custom
///   package: removable with its module, held to no layer rule but R10, R1 and
///   the cross-module line);
/// - a package outside all of those falls back to its name prefix, so a stray
///   `feature_x` is still judged as a feature.
///
/// Not the name first: a mis-named package (`zed_domain` in
/// `modules/zed/domain`) used to be classified `core` and escape R2, R3 and R10
/// altogether. R3 now also checks the name against the folder, so the two cannot
/// drift apart.
String _layerOf(MonorepoPackage pkg, String root) {
  final name = pkg.name;
  if (File(p.join(pkg.rootPath, 'app_manifest.yaml')).existsSync()) {
    return 'app';
  }
  if (_platformGroupOf(pkg, root) != null) return 'core';
  final segments = _segmentsBelow(pkg, root);
  if (segments.first == 'modules') {
    return switch (segments.length > 2 ? segments[2] : null) {
      'domain' => 'domain',
      'data' => 'data',
      'feature' => 'features',
      'api' => 'api',
      _ => 'module',
    };
  }
  if (name.startsWith('domain_')) return 'domain';
  if (name.startsWith('data_')) return 'data';
  if (name.startsWith('feature_')) return 'features';
  if (name == 'core_tools') return 'tools';
  // platform_kernel, core_*, *_state_management: the infrastructure ring.
  return 'core';
}

/// Every `.dart` file under `<packageRoot>/<dir>` (`test`, say), POSIX paths.
/// Empty when the folder does not exist.
List<String> _dartFilesUnder(String packageRoot, String dir) {
  final folder = Directory(p.posix.join(packageRoot, dir));
  if (!folder.existsSync()) return const [];
  return [
    for (final e in folder.listSync(recursive: true, followLinks: false))
      if (e is File && p.extension(e.path) == '.dart')
        p.posix.normalize(e.path.replaceAll(r'\', '/')),
  ];
}

/// Every `.dart` file of an app, wherever it sits (`lib/`, `test/`,
/// `integration_test/`, `test_driver/`, `tool/`), POSIX paths. Never walks the
/// directories no author writes in ([_unwalkedDirs]).
List<String> _appDartFiles(String appRoot) {
  final out = <String>[];
  void walk(Directory dir) {
    for (final e in dir.listSync(followLinks: false)) {
      final name = p.basename(e.path);
      if (e is Directory) {
        if (!_unwalkedDirs.contains(name)) walk(e);
      } else if (e is File && name.endsWith('.dart')) {
        out.add(p.posix.normalize(e.path.replaceAll(r'\', '/')));
      }
    }
  }

  walk(Directory(appRoot));
  return out;
}

/// The path segments of [pkg] relative to the repository [root] — never the
/// absolute path, which holds whatever directories the checkout happens to
/// live in (`~/modules/app`, `/srv/gen/ci`).
List<String> _segmentsBelow(MonorepoPackage pkg, String root) {
  final rel = p.posix.relative(pkg.rootPath.replaceAll(r'\', '/'), from: root);
  final segments = p.posix.split(rel);
  return segments.isEmpty ? const ['.'] : segments;
}

/// The module a package belongs to — `auth` for `modules/auth/data` — or
/// `null` for a package outside `modules/`.
///
/// Everything under `modules/` is removable, and a module is removed whole:
/// `remove_sample.dart auth` takes its domain, data and feature packages
/// together. So the module, not the single package, is what owns a contract.
/// Read from the path relative to [root]: the *first* segment must be
/// `modules`, so a checkout that sits under some other `modules/` directory
/// does not turn every package into a module package.
String? _moduleOf(MonorepoPackage pkg, String root) {
  final segments = _segmentsBelow(pkg, root);
  return segments.first == 'modules' && segments.length >= 2
      ? segments[1]
      : null;
}

/// R3: the name a package under `modules/<module>/<folder>` must carry, or
/// null when the folder is not one of the four layer folders. Names are how
/// the generators, composer and humans find a module's packages; a folder and
/// a name that disagree used to leave the package outside every layer rule.
String? _expectedModuleName(MonorepoPackage pkg, String root) {
  final segments = _segmentsBelow(pkg, root);
  if (segments.first != 'modules' || segments.length != 3) return null;
  final module = segments[1];
  return switch (segments[2]) {
    'domain' => 'domain_$module',
    'data' => 'data_$module',
    'feature' => 'feature_$module',
    'api' => '${module}_api',
    _ => null,
  };
}

/// R1: whether a platform package may not reach [target] at all — [target] is
/// a **workspace** package on the module side of the ring (anything living
/// under `modules/`), or one of the layer foundations under `platform/layers/`
/// (`domain_core`, `data_core`), where the approved-edge list decides.
///
/// A name never decides: `feature_discovery` from pub.dev is not upward of
/// anything. A hosted or SDK package is not in [packages].
bool _isUpwardOfPlatform(
  String target,
  Map<String, MonorepoPackage> packages,
  String root,
) {
  final pkg = packages[target];
  if (pkg == null) return false;
  return _moduleLayers.contains(_layers[target]) ||
      (_platformGroupOf(pkg, root) ?? '').startsWith('layers');
}

/// Whether [target] is a workspace package on the module side of the ring —
/// what a platform package's tests and dev dependencies may not reach either,
/// and for which no approved edge exists.
bool _isModuleRing(String target) => _moduleLayers.contains(_layers[target]);

/// R3: why [pkg] (a feature or a data package) may not depend on [dep], or
/// null when it may. Returns the noun phrase and the way out.
///
/// `Feature -> Domain <- Data`, and a module is a closed unit: a feature never
/// reaches another feature or any data package, a data package never reaches a
/// feature, and neither reaches **another module's** data, domain, API or
/// custom package. The one open door is a feature using another module's
/// `<id>_api` — the public surface made for exactly that.
///
/// [dep] is judged by where it lives in the workspace; a hosted package is
/// never a module package, whatever its name.
(String what, String hint)? _moduleLayerProblem(
  MonorepoPackage pkg,
  String layer,
  String dep,
  Map<String, MonorepoPackage> packages,
) {
  if (dep == pkg.name) return null;
  if (!packages.containsKey(dep)) return null;
  final targetLayer = _layers[dep];
  final same = _modules[dep] != null && _modules[dep] == _modules[pkg.name];
  const otherModule =
      'Reach another module through its `<id>_api` package (features only) '
      'or a product-neutral contract in core_di.';
  if (layer == 'features') {
    if (targetLayer == 'features') {
      return (
        'another feature',
        'Depend on that module\'s API package (`modules/<id>/api`, '
            '`<id>_api`) or a core_di contract instead.',
      );
    }
    if (targetLayer == 'data') {
      return ('data package', 'Features depend on domain, never on data.');
    }
    if (!same && (targetLayer == 'domain' || targetLayer == 'module')) {
      return (
        'another module\'s ${targetLayer == 'domain' ? 'domain' : 'custom'} '
            'package',
        otherModule,
      );
    }
  }
  if (layer == 'data') {
    if (targetLayer == 'features') {
      return (
        'feature',
        'Data implements domain contracts; it never reaches the UI layer.',
      );
    }
    if (!same && targetLayer == 'data') {
      return (
        'another module\'s data package',
        'A module\'s data stays private to it: go through its domain '
            'contract or its `<id>_api` package.',
      );
    }
    if (!same &&
        (targetLayer == 'domain' ||
            targetLayer == 'api' ||
            targetLayer == 'module')) {
      return (
        'another module\'s ${switch (targetLayer) {
          'domain' => 'domain',
          'api' => 'API',
          _ => 'custom',
        }} package',
        'A data package serves its own module only; another module\'s API '
            'is for features. Expose what is needed through a core_di '
            'contract.',
      );
    }
  }
  return null;
}

/// R16: the shell catalog (`SHELL_CONTRACTS` in `platform_app_shell`) names
/// every contract the shell looks up optionally.
///
/// An app declares, per catalog row, that it provides the contract or does
/// without it and why (`capabilities:`, RULE-81). That only holds if the
/// catalog is complete, so the rule goes the other way round: a `platform/`
/// package that resolves a `core_di` or module-API contract with
/// `getItOrNull<X>` / `getAllOrEmpty<X>` — and X is implemented only inside a
/// module, so it vanishes with that module, or by nobody at all, so an app
/// has to bring it — needs a `ShellContract<X>` row. And every row must name a
/// type some package declares, so a rename cannot leave a row nothing
/// satisfies.
///
/// Skipped in a workspace with no `platform_app_shell` or no catalog file.
List<Violation> _catalogViolations(
  String root,
  Map<String, MonorepoPackage> packages,
  Set<String> contractTypes,
  Map<String, Set<String>> removableContracts,
) {
  final shell = packages['platform_app_shell'];
  if (shell == null) return const [];
  final catalogFile = p.posix.join(shell.rootPath, kCatalogFile);
  if (!File(catalogFile).existsSync()) return const [];
  final catalogRel = p.posix.relative(catalogFile, from: root);

  final ShellCatalog catalog;
  try {
    catalog = parseCatalogSource(File(catalogFile).readAsStringSync());
  } on FormatException catch (e) {
    return [
      Violation(
        'R16',
        catalogRel,
        'the shell contract catalog cannot be read: ${e.message}',
      ),
    ];
  }

  final out = <Violation>[];
  final catalogued = {for (final row in catalog.entries) row.type};

  final declared = <String>{
    for (final pkg in packages.values) ...typesDeclaredIn(pkg.rootPath),
  };
  for (final row in catalog.entries) {
    if (declared.contains(row.type)) continue;
    out.add(
      Violation(
        'R16',
        catalogRel,
        '`ShellContract<${row.type}>` (`${row.id}`) names a type no package '
            'declares. A renamed or deleted contract left its row behind: '
            'rename the row, or delete it and the `capabilities:` entry that '
            'declares it in each app_manifest.yaml.',
      ),
    );
  }

  for (final pkg in packages.values) {
    final group = _platformGroupOf(pkg, root);
    if (group == null || group == 'invalid') continue;
    for (final file in dartFilesUnderLib(pkg.rootPath)) {
      if (isGeneratedSource(file, packageRoot: pkg.rootPath)) continue;
      for (final lookup in optionalLookupsIn(File(file).readAsStringSync())) {
        final type = lookup.type;
        if (!contractTypes.contains(type) || catalogued.contains(type)) {
          continue;
        }
        final owners = removableContracts[type];
        out.add(
          Violation(
            'R16',
            '${p.posix.relative(file, from: root)}:${lookup.line}',
            'the shell resolves `$type` optionally but `SHELL_CONTRACTS` has '
                'no row for it. ${owners == null ? 'No package registers it, so an app brings it' : 'It is implemented only in modules/${owners.join(', modules/')}'}'
                ' — add `ShellContract<$type>(...)` to $catalogRel so each '
                'app declares it under `capabilities:` (RULE-81), or resolve '
                'it somewhere that is not the shell.',
          ),
        );
      }
    }
  }
  return out;
}

/// Why an API package may not depend on [target], or null when it may.
///
/// Allowed: anything outside the workspace (Flutter, pub packages) and the
/// `platform/foundation/` group. Refused: every other platform package and
/// every module package — the owning module's domain/data/feature included,
/// and any other module's API.
String? _apiDependencyProblem(
  String target,
  Map<String, MonorepoPackage> packages,
  String root,
) {
  final pkg = packages[target];
  if (pkg == null) return null; // Flutter SDK / pub package
  if (_isModuleRing(target)) {
    return _apiPackages.contains(target)
        ? 'another module\'s API'
        : 'a module package';
  }
  final group = _platformGroupOf(pkg, root);
  if (group == 'foundation') return null;
  return group == null ? 'a workspace package' : 'platform/$group';
}

void main(List<String> args) {
  if (args.contains('--help') || args.contains('-h')) {
    _printHelp();
    exit(0);
  }
  // It takes no arguments. A flag it does not know (`--fix`, a typo of
  // `--help`) must not look like a clean run.
  if (args.isNotEmpty) {
    stderr.writeln('Unknown argument(s): ${args.join(' ')}');
    stderr.writeln('Usage: dart tools/arch_check/check.dart [--help]');
    exit(64);
  }

  OutputFormatter.printHeader(
    'Architecture Check',
    subtitle: 'Mechanical enforcement of docs/en/reference/01_rules.md',
  );

  final stopwatch = Stopwatch()..start();
  final root = p.posix.normalize(Directory.current.path.replaceAll(r'\', '/'));
  final packages = MonorepoHelper.getPackages(root);

  if (packages.isEmpty) {
    OutputFormatter.printError(
      'No workspace packages found. Run this from the repository root.',
    );
    exit(1);
  }

  for (final pkg in packages.values) {
    final layer = _layerOf(pkg, root);
    _layers[pkg.name] = layer;
    _modules[pkg.name] = _moduleOf(pkg, root);
    if (layer == 'api') _apiPackages.add(pkg.name);
  }

  OutputFormatter.printInfo(
    'Approved upward exceptions out of core/* '
    '(${_approvedUpwardEdges.length}):',
  );
  for (final entry in _approvedUpwardEdges.entries) {
    stdout.writeln('    • ${entry.key}');
    stdout.writeln('        ${entry.value}');
  }
  stdout.writeln('');

  final blocking = <Violation>[];
  final warnings = <Violation>[];

  // R8 needs a repo-wide view before the per-package pass: which `core_di`
  // contracts are implemented *only* inside a module, and therefore vanish
  // when that module is removed.
  // No `firstOrNull` here: it is a `package:collection` extension and this
  // tool deliberately depends only on `dart:io` and `package:path`.
  MonorepoPackage? coreDi;
  for (final pkg in packages.values) {
    if (pkg.name == 'core_di') {
      coreDi = pkg;
      break;
    }
  }
  // The contracts R8 governs: every type `core_di` declares, and every type a
  // module API package (`<module>_api`) declares — `AuthNavigator` is as
  // removable as a `core_di` contract only `feature_auth` implements.
  final contractTypes = <String>{
    if (coreDi != null) ...typesDeclaredIn(coreDi.rootPath),
    for (final pkg in packages.values)
      if (_apiPackages.contains(pkg.name)) ...typesDeclaredIn(pkg.rootPath),
  };
  final removableContracts = ownersImplementing([
    for (final pkg in packages.values)
      ScanUnit(_modules[pkg.name], pkg.rootPath),
  ], contractTypes);

  // R16 reads the same contracts: a shell lookup that is not in the catalog is
  // a contract no app is asked to decide about.
  blocking.addAll(
    _catalogViolations(root, packages, contractTypes, removableContracts),
  );

  final flutter = _FlutterClosure(root, packages);

  for (final pkg in packages.values) {
    final layer = _layers[pkg.name]!;
    // A domain package is recognised by where it lives — modules/<m>/domain,
    // or platform/layers/domain (`domain_core`, classified `core`): RULE-03
    // holds both.
    final isDomain =
        layer == 'domain' || _platformGroupOf(pkg, root) == 'layers/domain';
    final module = _modules[pkg.name];
    final allLib = dartFilesUnderLib(pkg.rootPath);
    final files = [
      for (final f in allLib)
        if (!isGeneratedSource(f, packageRoot: pkg.rootPath)) f,
    ];
    final testFiles = [
      for (final dir in const ['test', 'integration_test'])
        for (final f in _dartFilesUnder(pkg.rootPath, dir))
          if (!isGeneratedSource(f, packageRoot: pkg.rootPath)) f,
    ];
    final pubspecRel = p.posix.relative(
      p.posix.join(pkg.rootPath, 'pubspec.yaml'),
      from: root,
    );

    // Every way this package reaches another: an import in lib/, a declared
    // dependency, a dev dependency, an import in test/ or integration_test/.
    // Parsed from YAML by MonorepoHelper — a hand-rolled line scanner
    // silently drops entries after a blank line inside the block.
    final uses = <_Use>[
      for (final file in files)
        for (final ref in _scanFile(file).importedUris)
          _Use(
            ref.package,
            ref.dartLibrary,
            '${p.posix.relative(file, from: root)}:${ref.line}',
            _UseKind.import,
          ),
      for (final dep in pkg.dependencies)
        _Use(dep, null, pubspecRel, _UseKind.declared),
      for (final dep in pkg.devDependencies)
        _Use(dep, null, pubspecRel, _UseKind.dev),
      for (final file in testFiles)
        for (final ref in _scanFile(file).importedUris)
          _Use(
            ref.package,
            ref.dartLibrary,
            '${p.posix.relative(file, from: root)}:${ref.line}',
            _UseKind.testImport,
          ),
    ];

    // --- R1 / R2 / R3 / R9: forbidden edges --------------------------------
    // By import, by `dependencies:`, and — for the module ring — by
    // `dev_dependencies:` and by what test/ and integration_test/ import.
    // RULE-01 and RULE-04 say "imports or declares", and a dev dependency on a
    // module makes the platform or feature package as unextractable, and the
    // module as unremovable, as a real one.
    for (final u in uses) {
      final target = u.package;
      if (target == pkg.name) continue;

      if (layer == 'core' && target != null) {
        final edge = '${pkg.name} -> $target';
        final bool bad;
        if (u.kind.ships) {
          bad =
              _isUpwardOfPlatform(target, packages, root) &&
              !_approvedUpwardEdges.containsKey(edge);
        } else {
          // Tests and dev dependencies never ship, so a platform -> platform
          // edge is R11's business and exempt; a module is not.
          bad = _isModuleRing(target);
        }
        if (bad) {
          blocking.add(
            Violation(
              'R1',
              u.location,
              u.kind.isImport
                  ? 'core package `${pkg.name}` ${u.kind.verb} `$target`. '
                        'Core must not depend on an outer ring.'
                  : 'core package `${pkg.name}` ${u.kind.verb} `$target`. '
                        '${u.kind.ships ? 'Add it to _approvedUpwardEdges and RULE-01, or remove it.' : 'A test or dev dependency on a module still makes this package unextractable.'}',
            ),
          );
        }
      }

      if ((layer == 'features' || layer == 'data') && target != null) {
        final problem = _moduleLayerProblem(pkg, layer, target, packages);
        if (problem != null) {
          blocking.add(
            Violation(
              'R3',
              u.location,
              '`${pkg.name}` ${u.kind.verb} ${problem.$1} `$target`. '
                  '${problem.$2}',
            ),
          );
        }
      }

      // An API package is the public surface of its module: contracts over
      // the foundation and Flutter, nothing else. Importing its own module's
      // domain would leak that module's entities to every consumer; importing
      // any other module would chain removals.
      if (layer == 'api' && target != null) {
        final problem = _apiDependencyProblem(target, packages, root);
        if (problem != null) {
          blocking.add(
            Violation(
              'R3',
              u.location,
              'API package `${pkg.name}` ${u.kind.verb} `$target` ($problem). '
                  'An API package may depend on the foundation '
                  '(core_di, platform_kernel, core_common) and Flutter only.',
            ),
          );
        }
      }

      if (isDomain) {
        final problem = target != null
            ? _domainDependencyProblem(pkg, target, packages, root, flutter)
            : _dartLibraryProblem(u.dartLibrary);
        if (problem != null) {
          final what = target ?? 'dart:${u.dartLibrary}';
          blocking.add(
            Violation(
              'R2',
              u.location,
              'domain package `${pkg.name}` ${u.kind.verb} `$what` '
                  '($problem). Domain is pure Dart — it runs on a Dart VM, '
                  'tests included — and depends on `domain_core` and its own '
                  'module\'s domain only.',
            ),
          );
        }
      }

      // The pure-Dart tier. Checked in the pubspec as well as the imports: R2
      // once checked imports only, which is how `data_auth` kept a clean bill
      // of health while declaring firebase_auth and google_sign_in — Flutter
      // plugins that cannot run on a Dart VM — without a single
      // `package:flutter` import in its source.
      if (_isPureDartTier(pkg.name)) {
        final problem = target != null
            ? _pureDartProblem(target, flutter)
            : _dartLibraryProblem(u.dartLibrary);
        if (problem != null) {
          final what = target ?? 'dart:${u.dartLibrary}';
          blocking.add(
            Violation(
              'R9',
              u.location,
              '`${pkg.name}` is pure-Dart tier but ${u.kind.verb} `$what` '
                  '($problem). Move whatever needs it into a Flutter-side '
                  'package.',
            ),
          );
        }
      }
    }

    // R3: a package under modules/<m>/<layer> is named for its folder.
    final expectedName = _expectedModuleName(pkg, root);
    if (expectedName != null && pkg.name != expectedName) {
      blocking.add(
        Violation(
          'R3',
          pubspecRel,
          '`${pkg.name}` sits at ${_segmentsBelow(pkg, root).join('/')} and '
              'must be named `$expectedName` — the layer rules are read from '
              'the folder, and the generators, composer and reviewers find a '
              'module\'s packages by that name.',
        ),
      );
    }

    // --- R5: used but not declared ------------------------------------------
    for (final u in uses) {
      final target = u.package;
      if (u.kind != _UseKind.import || target == null) continue;
      final selfOrSdk = target == pkg.name || _sdkPackages.contains(target);
      if (selfOrSdk || pkg.dependencies.contains(target)) continue;
      blocking.add(
        Violation(
          'R5',
          u.location,
          '`${pkg.name}` imports `$target` but does not declare it in '
              '`dependencies:`. Pub Workspaces hide this locally; it '
              'breaks when the package is extracted.',
        ),
      );
    }

    // --- R11: platform group direction, by pubspec --------------------------
    // `dependencies:` only. A dev dependency never ships and never reaches a
    // consumer's graph: `platform_app_shell`'s tests use `core_storage` for
    // their fakes, and that is not an edge of the product graph. (A dev
    // dependency on a *module* is R1's.) Imports need no separate pass — R5
    // already holds every import to `dependencies:`.
    final group = _platformGroupOf(pkg, root);
    if (group == 'invalid') {
      blocking.add(
        Violation(
          'R11',
          pubspecRel,
          '`${pkg.name}` is not in a platform group folder. Move it to '
              'platform/<group>/<name>, <group> one of '
              '${_platformGroups.join(', ')}.',
        ),
      );
    } else if (group != null) {
      final allowed = _allowedGroupEdges[group]!;
      for (final dep in pkg.dependencies) {
        final target = packages[dep];
        if (target == null || dep == pkg.name) continue;
        // Every platform group sits below every module: a modules/ package is
        // a target no group may reach (R1 says the same).
        if (_isModuleRing(dep)) {
          blocking.add(
            Violation(
              'R11',
              pubspecRel,
              '`${pkg.name}` (platform/$group) depends on `$dep`, a package '
                  'under modules/. No platform group may reach a module.',
            ),
          );
          continue;
        }
        final targetGroup = _platformGroupOf(target, root);
        if (targetGroup == null || targetGroup == 'invalid') continue;
        if (allowed.contains(targetGroup)) continue;
        blocking.add(
          Violation(
            'R11',
            pubspecRel,
            '`${pkg.name}` (platform/$group) depends on `$dep` '
                '(platform/$targetGroup). $group may depend on '
                '${allowed.isEmpty ? 'no other platform package' : allowed.join(', ')}.',
          ),
        );
      }
    }

    // --- R4: shared constants belong in utils/ ----------------------------
    for (final file in files) {
      // Design-token exception: core_base_ui keeps its tokens in styles/,
      // which names the intent better than a generic utils/ bucket.
      final below = p.posix.relative(file, from: pkg.rootPath);
      if (below.contains('/utils/') || below.contains('/styles/')) continue;

      final content = File(file).readAsStringSync();
      final rel = p.posix.relative(file, from: root);
      for (final m in _publicStaticConst.allMatches(content)) {
        final line = '\n'.allMatches(content.substring(0, m.start)).length + 1;
        blocking.add(
          Violation(
            'R4',
            '$rel:$line',
            'public constant `${m.group(1)}` declared outside `utils/`. '
                'Move it so the package owns its constants in one place '
                '(private `_name` constants may stay where they are used).',
          ),
        );
      }
    }

    // --- R7: responsive sizing goes through BuildContext -------------------
    // `16.w` and `context.w(16)` return the same number, but only the second
    // registers an InheritedWidget dependency, so only the second rebuilds
    // when the metrics change (rotation, split-screen, desktop resize). The
    // bare form is therefore a silent staleness bug, not a style preference.
    // Every hand-written Dart file under lib/ is read — a file that never
    // imports core_responsive can still declare or reach a `num` extension of
    // the same name.
    for (final file in files) {
      final scanned = _scanFile(file);
      final rel = p.posix.relative(file, from: root);
      // A number, or a parenthesised sum, followed by a sizing extension.
      for (final f in bareSizingExtensionsIn(scanned)) {
        blocking.add(
          Violation(
            'R7',
            '$rel:${f.line}',
            'bare `.${f.text}` sizing extension — use '
                '`context.${f.text}(value)` so the widget rebuilds when '
                'screen metrics change. If no BuildContext is reachable, '
                'read the value from one before the first `await` and pass '
                'it in.',
          ),
        );
      }
      // The extension that would make the bare form compile.
      for (final f in sizingExtensionDeclarationsIn(scanned)) {
        blocking.add(
          Violation(
            'R7',
            '$rel:${f.line}',
            'an extension on `num` declares `${f.text}`: it makes a bare '
                '`16.${f.text}` type-check while reading a value that never '
                'notifies anyone. Scaling goes through '
                '`context.${f.text}(value)`; rename or delete it.',
          ),
        );
      }
    }

    // --- R8: removable contracts resolve optionally ------------------------
    // `getAll<T>()` throws when `T` is unregistered and `getIt<T>()` throws
    // when nothing implements it. For a contract whose only implementers
    // live in a module, that is a crash the moment the module is removed —
    // and modules are removable by design (RULE-05). The failure is
    // invisible to `flutter analyze` because the lookup type-checks fine; it
    // surfaces at runtime, on whichever screen happens to call it.
    for (final file in files) {
      final scanned = _scanFile(file);
      final rel = p.posix.relative(file, from: root);
      for (final lookup in throwingLookupsIn(scanned)) {
        final type = lookup.text;
        final owners = removableContracts[type];
        if (owners == null) continue;
        // The owning module may resolve its own contract eagerly: if one
        // of its packages is in the build, so is the registration.
        if (module != null && owners.contains(module)) continue;

        blocking.add(
          Violation(
            'R8',
            '$rel:${lookup.line}',
            '`$type` is implemented only in modules/${owners.join(', modules/')}, '
                'which is removable — a throwing lookup here crashes any '
                'build without it. Use `getItOrNull<$type>()` (or '
                '`getAllOrEmpty`) and handle the null case.',
          ),
        );
      }

      // The same crash, hidden in the generated wiring: a class outside every
      // module that DI builds with a module-owned contract as a required
      // parameter. Injectable resolves it with a throwing `get`, so the whole
      // graph fails to build once the module is gone. Nullable parameters and
      // `@factoryParam` ones are optional, and are not reported.
      if (module == null) {
        for (final param in injectedParametersIn(scanned)) {
          final owners = removableContracts[param.type];
          if (owners == null) continue;
          blocking.add(
            Violation(
              'R8',
              '$rel:${param.line}',
              'an injectable class takes `${param.type}` as a required '
                  'constructor parameter, but it is implemented only in '
                  'modules/${owners.join(', modules/')}, which is removable — '
                  'DI cannot build this class without it. Make the parameter '
                  'nullable (`${param.type}?`) and have the route pass '
                  '`getItOrNull<${param.type}>()` as a `@factoryParam`, or '
                  'resolve the contract at the call site with '
                  '`getItOrNull`.',
            ),
          );
        }
      }
    }

    // --- R10: the app shell composes modules, it does not import them ------
    // Removability is the property the whole composition design exists to
    // protect, and exactly one file is allowed to break it: the composition
    // root, which must name what it composes.
    //
    // Everywhere else in an app, a module import is fatal in a way no
    // `getItOrNull` guard can soften — an unresolved import fails at compile
    // time, before any lookup runs. `network_config_impl.dart` imported
    // `data_auth` and `domain_auth` for exactly this reason and made the auth
    // module unremovable while every document claimed otherwise.
    //
    // The whole app is held to the same line, not only lib/ and test/: a test,
    // an integration test, a driver or a tool that names a module is a build
    // that stops compiling when the module is removed, and a removed module is
    // exactly what the smoke test exists to prove boots. Only the composition
    // root `lib/di/injection.dart` may name a module.
    if (layer == 'app') {
      final compositionRoot = p.posix.join(pkg.rootPath, _compositionRoot);
      for (final file in _appDartFiles(pkg.rootPath)) {
        if (isGeneratedSource(file, packageRoot: pkg.rootPath)) continue;
        if (p.posix.normalize(file) == compositionRoot) continue;
        final rel = p.posix.relative(file, from: root);
        for (final ref in _scanFile(file).importedUris) {
          final target = ref.package;
          if (target == null || !_isModulePackage(target)) continue;
          blocking.add(
            Violation(
              'R10',
              '$rel:${ref.line}',
              'the app imports `$target`. Only `$_compositionRoot` may name '
                  'a module (its API package included); everywhere else '
                  'declare a contract in `core_di` and resolve it with '
                  '`getItOrNull`. A type import cannot be guarded — it fails '
                  'the build the moment that module is removed.',
            ),
          );
        }
      }
    }

    // --- R6: a file named like generated output carries the header ---------
    // A hand-written `size_ext.g.dart` is not generated: it is read by every
    // other rule as the hand-written code it is (isGeneratedSource wants the
    // generator's header), and reported here.
    for (final file in allLib) {
      final name = p.posix.basename(file);
      final isConventional =
          name.endsWith('.g.dart') ||
          name.endsWith('.freezed.dart') ||
          name.endsWith('.config.dart') ||
          name.endsWith('.module.dart');
      if (!isConventional ||
          isGeneratedSource(file, packageRoot: pkg.rootPath)) {
        continue;
      }
      blocking.add(
        Violation(
          'R6',
          p.posix.relative(file, from: root),
          'named like generated output but carries no generator header, so it '
              'is hand-written (or hand-edited) code under a name that hides '
              'it. Regenerate it with `dart run build_runner build '
              '--workspace`, or give it an ordinary name.',
        ),
      );
    }
  }

  // --- R12-R15: repository-wide source hygiene ----------------------------
  // These look at files rather than at the package graph, so they run once
  // over the working tree instead of once per package.
  blocking.addAll(_hygieneViolations(root));

  stopwatch.stop();
  _report(packages.length, blocking, warnings, stopwatch.elapsed);
  exit(blocking.isEmpty ? 0 : 1);
}

/// Directories never walked by the repository-wide rules: VCS and tool
/// state, build output, and the native dependency trees Flutter and
/// CocoaPods fetch. None of it is authored in this repository.
const _unwalkedDirs = <String>{
  '.git',
  '.dart_tool',
  '.fvm',
  '.idea',
  '.symlinks',
  '.pub-cache',
  'build',
  'coverage',
  'ephemeral',
  'node_modules',
  'Pods',
};

/// Every file in the working tree that git does not ignore, as repo-relative
/// POSIX paths — tracked files plus new files about to be added.
///
/// Walked from disk rather than read from `git ls-files`, so a module
/// checked out as a submodule is scanned too (`ls-files` stops at the
/// gitlink) and a fixture outside any git checkout still works. When git is
/// available, whatever it reports as ignored (`firebase_options_*.dart`,
/// local env files, …) is dropped afterwards.
List<String> _workingTreeFiles(String root) {
  final out = <String>[];
  void walk(Directory dir) {
    for (final e in dir.listSync(followLinks: false)) {
      final name = p.basename(e.path);
      if (e is Directory) {
        if (_unwalkedDirs.contains(name)) continue;
        walk(e);
      } else if (e is File) {
        out.add(
          p.posix.relative(e.path.replaceAll(r'\', '/'), from: root),
        );
      }
    }
  }

  walk(Directory(root));
  final ignored = _gitIgnored(root);
  if (ignored.isEmpty) return out..sort();
  bool isIgnored(String rel) {
    if (ignored.contains(rel)) return true;
    // `--directory` reports a wholly ignored folder once, as `dir/`.
    var dir = p.posix.dirname(rel);
    while (dir != '.' && dir != '/') {
      if (ignored.contains('$dir/')) return true;
      dir = p.posix.dirname(dir);
    }
    return false;
  }

  return out.where((f) => !isIgnored(f)).toList()..sort();
}

/// Paths git ignores under [root] (folders as `dir/`), or an empty set when
/// [root] is not the top of a git checkout or git is not installed.
Set<String> _gitIgnored(String root) {
  try {
    final top = Process.runSync('git', [
      'rev-parse',
      '--show-toplevel',
    ], workingDirectory: root);
    if (top.exitCode != 0) return const {};
    final topPath = p.posix.normalize(
      '${top.stdout}'.trim().replaceAll(r'\', '/'),
    );
    // A fixture in a temp dir nested inside some other checkout must not
    // inherit that checkout's ignore rules.
    if (topPath != root) return const {};
    final r = Process.runSync('git', [
      'ls-files',
      '-z',
      '--others',
      '--ignored',
      '--exclude-standard',
      '--directory',
    ], workingDirectory: root);
    if (r.exitCode != 0) return const {};
    return '${r.stdout}'.split('\x00').where((s) => s.isNotEmpty).toSet();
  } on ProcessException {
    return const {};
  }
}

/// An analyzer suppression the analyzer honours: `// ignore: rule`, the same
/// after any run of slashes (`/// ignore: rule` and `//// ignore: rule` both
/// silence the next line — probed with `dart analyze`), or
/// `// ignore_for_file: rule`. `/// ignore_for_file:` is **not** honoured, so it
/// is not matched. Case matters (`// IGNORE:` does nothing), and the marker must
/// open the comment: `// why // ignore: x` is prose. Matched against the text of
/// a real line comment only (see [DartSource]), so the same words inside a
/// string literal do not count either.
final _suppression = RegExp(r'^(?://+\s*(ignore)|//\s*(ignore_for_file))\s*:');

/// A class declaration whose name has the interface prefix `I[A-Z]`, with
/// its modifiers and any same-line annotations in front of it.
final _interfaceNamedClass = RegExp(
  r'^[ \t]*(?:@[\w.]+(?:\([^)\n]*\))?\s+)*'
  r'((?:(?:abstract|sealed|base|final|interface|mixin)\s+)*)'
  r'class\s+(I[A-Z]\w*)',
  multiLine: true,
);

/// R12-R15, over every non-ignored file in the working tree.
List<Violation> _hygieneViolations(String root) {
  final out = <Violation>[];
  final files = _workingTreeFiles(root);
  // Directory -> the package that owns it, so a folder is resolved once.
  final packageRoots = <String, String>{};

  // R17's own list: an exception with no reason is not an exception.
  for (final problem in allowListProblems(kPlatformForkAllowList)) {
    out.add(Violation('R17', 'tools/arch_check/platform_forks.dart', problem));
  }
  // An entry whose file is gone (renamed, deleted) is as dead as one whose file
  // stopped forking. Only in the tree that owns the list: a fixture or a
  // partial checkout has none of these files and is not asked for them.
  if (File(p.join(root, 'tools/arch_check/platform_forks.dart')).existsSync()) {
    for (final rel in kPlatformForkAllowList.keys) {
      if (File(p.join(root, rel)).existsSync()) continue;
      out.add(
        Violation(
          'R17',
          rel,
          'allow-listed for platform forks, but the file does not exist. '
              'Remove or rename the entry in `kPlatformForkAllowList` in '
              'tools/arch_check/platform_forks.dart.',
        ),
      );
    }
  }

  for (final rel in files) {
    final segments = p.posix.split(rel);

    // --- R12: no PowerShell ------------------------------------------------
    // Windows' default execution policy refuses to run an unsigned .ps1, so
    // a script that works for its author fails for the next contributor.
    if (rel.toLowerCase().endsWith('.ps1')) {
      out.add(
        Violation(
          'R12',
          rel,
          'PowerShell script. The default Windows execution policy blocks '
              'it — write a cross-platform Dart script under tools/ instead '
              '(.sh/.bat only when Dart cannot do the job).',
        ),
      );
      continue;
    }

    // --- R13: no package-local analyzer configuration ----------------------
    // The root analysis_options.yaml is the one lint set (changing it is held
    // by review). A package-local file replaces it for that package and can
    // switch any rule off with no `// ignore` for R13's comment scan to see.
    if (p.posix.basename(rel) == 'analysis_options.yaml' &&
        segments.length > 1) {
      out.add(
        Violation(
          'R13',
          rel,
          'package-local analysis_options.yaml. Only the repository root '
              'holds one: a nested file silently replaces the shared lint set '
              'for its package. Delete it and fix what it was hiding.',
        ),
      );
      continue;
    }

    if (!rel.endsWith('.dart')) continue;
    // Generated Dart is nobody's to write: not its comments, not its class
    // names, and a generator is entitled to its `ignore_for_file`. Judged by
    // the same test as every other rule (isGeneratedSource: name or folder
    // *and* the generator's header), against the package-relative path.
    final abs = p.posix.join(root, rel);
    if (isGeneratedSource(
      abs,
      packageRoot: packageRoots.putIfAbsent(
        p.posix.dirname(abs),
        () => packageRootOf(abs, root),
      ),
    )) {
      continue;
    }

    final inProductTree =
        segments.first == 'modules' ||
        segments.first == 'platform' ||
        (segments.first == 'apps' &&
            segments.length > 2 &&
            segments[2] == 'lib');

    final String source;
    try {
      source = File(p.join(root, rel)).readAsStringSync();
    } on FileSystemException {
      continue; // not UTF-8, or vanished mid-run: not ours to judge
    }
    final scanned = DartSource.scan(source);

    // --- R13: no analyzer suppressions -----------------------------------
    for (final comment in scanned.lineComments) {
      final m = _suppression.firstMatch(comment.text);
      if (m == null) continue;
      out.add(
        Violation(
          'R13',
          '$rel:${comment.line}',
          '`${comment.text.trim().split(':').first}:` suppresses the analyzer. '
              'Fix the cause — for a deprecation, migrate to the replacement '
              'API — instead of silencing it.',
        ),
      );
    }

    // --- R17: platform forks are an app decision --------------------------
    if (isForkScanned(rel)) {
      final sites = forkSitesIn(scanned);
      final reason = kPlatformForkAllowList[rel];
      if (reason == null) {
        for (final site in sites) {
          out.add(
            Violation(
              'R17',
              '$rel:${site.line}',
              '`${site.text}` forks on the platform outside the allow-list. '
                  'What an app does on a platform is declared in its '
                  'manifest and read from `PlatformFacts` (RULE-82); the only '
                  'place that asks the Flutter runtime is '
                  '`resolveAppPlatform()`. If this is an OS API that does not '
                  'exist everywhere, add the file to `kPlatformForkAllowList` '
                  'in tools/arch_check/platform_forks.dart with the reason.',
            ),
          );
        }
      } else if (sites.isEmpty) {
        out.add(
          Violation(
            'R17',
            rel,
            'allow-listed for platform forks ($reason), but the file no '
                'longer forks. Remove the entry from `kPlatformForkAllowList` '
                'in tools/arch_check/platform_forks.dart.',
          ),
        );
      }
    }

    // --- R18: Bloc event handlers are async (RULE-52) ---------------------
    if (isForkScanned(rel)) {
      for (final f in blocHandlerProblemsIn(scanned)) {
        out.add(
          Violation(
            'R18',
            '$rel:${f.line}',
            'an `on<Event>` handler that is not async: ${f.text}. Declare '
                'it `Future<void> ... async` and take `(event, emit)` — a '
                'sync handler returns before its awaited work finishes, and '
                'the late `emit` throws "emit was called after an event '
                'handler completed normally".',
          ),
        );
      }
    }

    // --- R19: runtime diagnostics go through DynamicLogger (RULE-65) -------
    if (isProductLib(rel)) {
      for (final f in diagnosticCallsIn(scanned)) {
        out.add(
          Violation(
            'R19',
            '$rel:${f.line}',
            '`${f.text}(` writes to the console. Runtime diagnostics go '
                'through `DynamicLogger.log` so they can be filtered and '
                'stay out of release logs (tests and tools are not scanned: '
                'tools write with `stdout.writeln`).',
          ),
        );
      }
    }

    // --- R20: no raw layout numbers in widgets (RULE-30, RULE-33) ----------
    if (isProductLib(rel) && !isConstantsHome(rel)) {
      for (final f in rawLayoutNumbersIn(scanned)) {
        out.add(
          Violation(
            'R20',
            '$rel:${f.line}',
            'raw number in `${f.text}`. Take layout and paint values from '
                '`context.w/h/sp/r` or a design token (`AppSpacing`, '
                '`AppRadius`); constants live under styles/ or utils/.',
          ),
        );
      }
    }

    // --- R15: the I prefix is reserved for interfaces --------------------
    if (inProductTree) {
      for (final m in _interfaceNamedClass.allMatches(scanned.code)) {
        final modifiers = m.group(1)!.split(RegExp(r'\s+'));
        final isInterface =
            modifiers.contains('abstract') ||
            modifiers.contains('interface') ||
            modifiers.contains('sealed');
        if (isInterface) continue;
        final name = m.group(2)!;
        out.add(
          Violation(
            'R15',
            '$rel:${scanned.lineOf(m.end - name.length)}',
            'concrete class `$name` carries the interface prefix `I`. '
                'Declare it `abstract` / `interface` / `sealed`, or drop the '
                'prefix — an implementation is `${name.substring(1)}Impl`.',
          ),
        );
      }
    }
  }

  // --- R14: data_sources/, never datasources/ -----------------------------
  // Walked as directories so an empty `datasources/` is caught as well.
  for (final top in const ['modules', 'platform', 'apps']) {
    final dir = Directory(p.join(root, top));
    if (!dir.existsSync()) continue;
    void walk(Directory d) {
      for (final e in d.listSync(followLinks: false)) {
        if (e is! Directory) continue;
        final name = p.basename(e.path);
        if (_unwalkedDirs.contains(name)) continue;
        if (name.toLowerCase() == 'datasources') {
          out.add(
            Violation(
              'R14',
              p.posix.relative(e.path.replaceAll(r'\', '/'), from: root),
              'directory `$name/` — the convention is `data_sources/` '
                  '(data_sources/remote, data_sources/local).',
            ),
          );
        }
        walk(e);
      }
    }

    walk(dir);
  }
  return out;
}

void _report(
  int packageCount,
  List<Violation> blocking,
  List<Violation> warnings,
  Duration elapsed,
) {
  const ruleTitles = <String, String>{
    'R1': 'Dependency direction (platform must not reach modules)',
    'R2': 'Domain is pure Dart',
    'R3': 'Module layer boundaries (feature, data, API)',
    'R4': 'Package constants live in utils/',
    'R5': 'Every import is declared',
    'R6': 'Generated files are not hand-edited',
    'R7': 'Responsive sizing goes through BuildContext',
    'R8': 'Removable contracts resolve optionally',
    'R9': 'The pure-Dart tier stays pure',
    'R10': 'The app shell composes modules, it does not import them',
    'R11': 'Platform group direction',
    'R12': 'No PowerShell scripts',
    'R13': 'No analyzer suppressions or package-local lint config',
    'R14': 'Data source folders are data_sources/',
    'R15': 'The I prefix is reserved for interfaces',
    'R16': 'The shell contract catalog is complete',
    'R17': 'Platform forks are an app decision',
    'R18': 'Bloc event handlers are async',
    'R19': 'Runtime diagnostics go through DynamicLogger',
    'R20': 'No raw numeric literals for layout and paint',
  };

  if (warnings.isNotEmpty) {
    OutputFormatter.printWarning('${warnings.length} warning(s):');
    for (final w in warnings) {
      stdout.writeln('    ${w.location}');
      stdout.writeln('      ${w.message}');
    }
    stdout.writeln('');
  }

  if (blocking.isEmpty) {
    OutputFormatter.printSuccess(
      'All architecture rules hold across $packageCount packages.',
    );
    OutputFormatter.printTiming('Architecture check', elapsed);
    return;
  }

  final byRule = <String, List<Violation>>{};
  for (final v in blocking) {
    byRule.putIfAbsent(v.rule, () => []).add(v);
  }

  OutputFormatter.printError(
    '${blocking.length} violation(s) across ${byRule.length} rule(s):',
  );
  stdout.writeln('');

  final ids = byRule.keys.toList()..sort();
  for (final id in ids) {
    OutputFormatter.printSection(
      '$id — ${ruleTitles[id] ?? ''}',
      icon: '🚫',
    );
    for (final v in byRule[id]!) {
      stdout.writeln('    ${v.location}');
      stdout.writeln('      ${v.message}');
    }
    stdout.writeln('');
  }

  OutputFormatter.printInfo(
    'Rules and rationale: docs/en/reference/01_rules.md (the RULE-NN registry)',
  );
  OutputFormatter.printTiming('Architecture check', elapsed);
}

void _printHelp() {
  stdout.writeln('''
Architecture Check — enforces the layering rules in docs/en/reference/01_rules.md.

USAGE
  dart tools/arch_check/check.dart [--help]

Run from the repository root. Exits 0 when clean, 1 on any blocking violation,
so it can gate CI.

HOW EDGES ARE READ
  Imports come from a lexer, not a line regex: every `import` / `export`
  directive in hand-written Dart, with every URI it names — the first one and
  each `if (...) 'uri'` configuration of a conditional import — however it is
  spelled (`import'x';`, two directives on a line, a wrapped `show` clause).
  A directive-looking line inside a block comment or a string is not one.
  A package is judged by where it lives in the workspace, never by its name:
  a hosted `feature_discovery` or `data_table_2` is third-party code, and a
  package under modules/<m>/{domain,data,feature,api} is a domain / data /
  feature / API package whatever it is called (R3 checks the name matches its
  folder). Paths are read relative to the repository, so the directory the
  checkout lives in (`~/gen/app`, `/srv/modules/ci`) changes nothing.

RULES CHECKED
  R1  Dependency direction
      No package under platform/ — every group, platform/layers/data
      (data_core) and platform/layers/domain (domain_core) included — may
      import or declare a workspace package living under modules/ (a domain,
      data, feature, API or custom package), nor domain_core / data_core except
      for the approved edges listed at the top of the run. A platform package
      is recognised by its folder, not by its name. Checked in lib/ imports
      and pubspec.yaml `dependencies:`, and — for module targets, which have no
      approved edge — in `dev_dependencies:` and in test/ and
      integration_test/ imports as well: a dev dependency on a module still
      makes the package unextractable and the module unremovable.
      (platform -> platform dev dependencies stay exempt: R11.)

  R2  Domain is pure Dart
      A domain package (modules/<m>/domain, or domain_core) may not import or
      declare — under `dependencies:` or `dev_dependencies:`, and in test/ —
      flutter (or flutter_test, any package that depends on the Flutter SDK or
      is a Flutter plugin, found through the pubspecs pub resolved,
      `.dart_tool/package_config.json`), material_ui, cupertino_ui, go_router,
      provider, flutter_bloc, dio, retrofit, drift or http, nor a workspace
      package other than domain_core and a domain package of its own module
      (no platform package, no data / feature / API / custom package, no other
      module's domain). A domain test therefore runs on `package:test` (RULE-60).
      Nor may it import an engine- or browser-only Dart library: dart:ui,
      dart:html, dart:js, dart:js_interop(_unsafe), dart:js_util, dart:web_ui,
      dart:web_gl, dart:web_audio, dart:web_sql, dart:indexed_db, dart:svg.
      (dart:io is not banned: whether a domain may use it is undecided.)

  R3  Module layer boundaries (Feature -> Domain <- Data)
      A feature may not import or declare another feature, any data_* package,
      or another module's domain or custom package. A data package may not
      import or declare a feature, nor another module's data, domain, API or
      custom package (data_core and its own module's packages are fine).
      Cross-feature work goes through the other module's API package
      (modules/<id>/api, named <id>_api — open to features only) or a
      product-neutral contract in core_di. An API package (<id>_api under
      modules/) may depend on platform/foundation/ packages and Flutter/pub
      packages only — never on its own module's domain/data/feature, another
      module's package or API, or any other platform group. Checked in lib/
      imports, `dependencies:`, `dev_dependencies:` and test/ and
      integration_test/ imports. And a package at modules/<m>/<layer> must be
      named for its folder: domain_<m>, data_<m>, feature_<m>, <m>_api — the
      layer rules read the folder, so a mis-named package is reported rather
      than silently classified.

  R4  Package constants live in utils/
      A *public* `static const` must sit in a `utils/` directory (in practice
      lib/src/utils/). Files under a `styles/` directory are exempt — that is
      where core_base_ui keeps its design tokens. Private `_name` constants may
      stay beside the code that uses them. A package with no shared constants
      needs no utils/ directory — this rule never asks for an empty folder.

  R5  Every import is declared
      Every `package:X` used under lib/ must appear in that package's
      `dependencies:`. Pub Workspaces share one package_config.json, so an
      undeclared import still compiles locally and only breaks on extraction.

  R6  Generated files are not hand-edited
      A file named *.g.dart / *.freezed.dart / *.config.dart / *.module.dart
      must carry its generator header (`GENERATED CODE - DO NOT MODIFY BY
      HAND` or the like, in the leading comment). One without it is
      hand-written code under a name that hides it: it is reported here AND
      read by every other rule as the hand-written file it is.

  R7  Responsive sizing goes through BuildContext
      `16.w` and `context.w(16)` compute the same number, but only the
      second registers an InheritedWidget dependency, so only the second
      rebuilds when metrics change (rotation, split-screen, resize).
      Checked in every hand-written Dart file under lib/ of every package
      (comments and string literals blanked), not only in files that import
      core_responsive: an extension declared elsewhere type-checks too.
      The receiver is a number literal (`16.w`, `1.5.sp`, `.5.h`), or a
      parenthesised arithmetic group (`(4 + 4).h`, `(gap * 2).w`), with the
      dot on the same line or the next (`16\n  .w`). A call's result is not a
      receiver: `Color.fromARGB(...).r`, `c.withValues(alpha: .5).r` and
      `Size(a, b).h` are members of the result, not sizing. Also reported: a
      workspace `extension ... on num|int|double` that declares a member named
      w, h, r, sp, spMin, dg or dm — what would make the bare form compile.
      Limitation: a *variable* receiver (`final p = 8; p.w`, `Pad.md.w`) is
      not followed, since without types `.r` there may be `Color.r`.

  R8  Removable contracts resolve optionally
      A `core_di` contract or a module API type (declared in any <id>_api
      package) implemented only under modules/ (any layer — a data
      package's gateway as much as a feature's navigator) disappears when
      that module is removed. `getIt<T>()` and `getAll<T>()` throw in
      that case, so such a type must be resolved with `getItOrNull<T>()` /
      `getAllOrEmpty<T>()` and a fallback. Packages of the implementing
      module may still resolve its contracts eagerly.
      Read on comment- and string-stripped source, so every spelling counts:
      getIt<T>(), getIt.get<T>(), getIt.getAll<T>(), getIt.getAsync<T>(),
      GetIt.I<T>(), GetIt.instance<T>(), a type argument split over lines, and
      an untyped `final T x = getIt();` (the declared type is the lookup).
      Also through any alias of a GetIt declared or initialised in the same
      file: a `final GetIt _getIt;` field (`_getIt.get<T>()`, `_getIt<T>()`,
      `this._getIt...`), an injected `GetIt locator` parameter, a local
      `final sl = GetIt.instance;`. An alias that crosses files (a `locator`
      inherited from a base class elsewhere) cannot be placed.
      Who implements a contract is read from code too, never from prose: a
      comment saying "implements IThemeStorage" makes nothing an implementer,
      and `implements c.IFoo` (an import prefix) or `@LazySingleton(as: c.IFoo)`
      counts like the plain spelling.
      Also: an `@injectable` / `@lazySingleton` / `@singleton` class outside
      every module whose constructor takes such a contract as a required
      parameter (non-nullable, not `@factoryParam`) is reported — injectable
      resolves it with a throwing get, so the graph stops building once the
      module is gone. Both field-formal (`this._x`) and typed parameters are
      read; a parameter the scan cannot type is left alone.
      Invisible to `flutter analyze`: the lookup type-checks, then crashes at
      runtime on whichever screen calls it.

  R9  The pure-Dart tier stays pure
      `platform_kernel` must neither import nor declare in `pubspec.yaml`
      (`dependencies:` and `dev_dependencies:`, and in its test/):
      Flutter and its bound packages (material_ui, cupertino_ui,
      flutter_localizations, flutter_web_plugins, go_router, provider,
      flutter_bloc), the transport and persistence libraries (dio, retrofit,
      drift, http), or any package that is a Flutter plugin or depends on the
      Flutter SDK, directly or through other packages (read from the
      workspace pubspecs and `.dart_tool/package_config.json`), flutter_test
      included, nor an engine- or browser-only Dart library (the R2 list:
      dart:ui, dart:html, dart:js_interop, ...). The pubspec half matters: a
      package can declare a Flutter plugin and never write
      `import 'package:flutter/...'`.

  R10 The app shell composes modules, it does not import them
      In an app (a package with app_manifest.yaml), only lib/di/injection.dart
      — the composition root, matched as that exact path — may import a
      package living under modules/ (domain, data, feature, API or custom).
      Anywhere else in the app — lib/, test/, integration_test/, test_driver/,
      tool/, every .dart file under the app root bar generated output — a
      module import is an unguardable compile-time dependency: the build
      breaks the moment that module is removed. A hosted package with a
      module-like name is not a module package.

  R11 Platform group direction
      Every package under platform/ sits in a group folder,
      platform/<group>/<package>, and may declare (under `dependencies:`)
      platform packages of these groups only:
        layers/domain (domain_core)  nothing — the leaf
        foundation                   foundation, layers/domain
        layers (data_core, other)    foundation, layers/domain
        infra                        foundation, layers — no infra -> infra
        ui                           foundation, ui
        state                        foundation, layers, ui
        shell                        every group
      The group comes from the folder, the one thing that records it.
      dev_dependencies are not checked: they never ship (the shell's tests
      use core_storage for fakes). A package directly under platform/, or in
      an unknown group folder, is itself a violation.

  R12 No PowerShell scripts
      No *.ps1 file anywhere in the working tree. Windows' default execution
      policy refuses unsigned scripts, so one that runs for its author fails
      for the next contributor. Write a cross-platform Dart script instead
      (.sh/.bat only when Dart cannot do the job).

  R13 No analyzer suppressions in hand-written Dart
      No `// ignore: <rule>`, `/// ignore: <rule>` or `//// ignore: <rule>`
      (the analyzer honours `ignore:` after any run of slashes — probed with
      `dart analyze`), no `//ignore:x`, trailing `// ignore:` or
      `// ignore_for_file: <rule>` comment in any .dart file of the repository
      (tools/, test/ and apps/ included). Fix the cause; for a deprecation,
      migrate to the replacement API. Only real line comments that OPEN with
      the marker count: the analyzer does not honour `/// ignore_for_file:`,
      `/* ignore: x */`, `// IGNORE: x` or `// why // ignore: x`, and neither
      does this rule; the same words inside a string literal are text.
      And no analysis_options.yaml except the repository root's: a
      package-local file replaces the shared lint set for its package and can
      switch rules off where no comment scan can see it. (Editing the root
      file stays a review matter.)

  R14 Data source folders are data_sources/
      No directory named `datasources` (any letter case) under modules/,
      platform/ or apps/. The convention is data_sources/remote and data_sources/local.
      Checked on directories, so an empty one is reported too.

  R15 The I prefix is reserved for interfaces
      In hand-written Dart under modules/, platform/ and apps/*/lib, a class
      whose name matches I[A-Z]... must be declared `abstract`, `interface`
      or `sealed` (e.g. `abstract class IAuthRepository`, `abstract interface
      class IFoo`). A concrete class — plain, `base`, `final`, or a `mixin
      class` without `abstract` — is reported; name it `<Name>Impl`. A plain
      `mixin IFoo` is not a class declaration and is not checked.
      Limitations: a lexical scan, not a parser. Declarations are matched at
      the start of a line (after any same-line annotations), with comments
      and string literals blanked out first, so generator templates and
      examples in docs comments do not count. A two-letter acronym at the
      start of a concrete class (`IOClient`) is reported as well — rename it
      or make it abstract; longer acronyms are written as words in Dart
      (`IosConfig`), which does not match.

  R16 The shell contract catalog is complete
      `platform_app_shell` keeps one table of what the shell resolves from
      dependency injection (`SHELL_CONTRACTS`); each app declares every
      optional row under `capabilities:` as provided, or absent with a reason
      (RULE-81). So (a) every `core_di` or module-API contract that a platform/
      package resolves with `getItOrNull<X>` / `getAllOrEmpty<X>` — and that is
      implemented only inside a module, or by nobody — needs a
      `ShellContract<X>` row, and (b) every row's type must be declared by some
      package. Adding a shell lookup without cataloguing it fails here, so the
      catalog cannot rot. Skipped when there is no platform_app_shell catalog.

  R17 Platform forks are an app decision
      `Platform.isX`, `Platform.operatingSystem`, `kIsWeb`,
      `defaultTargetPlatform` and `TargetPlatform.` in hand-written Dart under
      platform/*/lib, modules/*/lib and apps/*/lib (comments and strings
      blanked) may appear only in the files of `kPlatformForkAllowList`
      (tools/arch_check/platform_forks.dart), each with a reason: the one
      policy fork `resolveAppPlatform()`, and OS-API availability sites. An
      entry with no reason, or for a file that no longer forks or exists, is
      itself a violation (RULE-82).

  R18 Bloc event handlers are async  (RULE-52)
      In hand-written Dart under platform/*/lib, modules/*/lib and apps/*/lib
      every `on<Event>(handler)` registration must hand over an async handler:
      an inline closure has to be `(event, emit) async ...`, and a tear-off
      (`on<E>(_onE)`) has to resolve — in the same file — to a method declared
      `Future<void> _onE(...) async`. A sync handler returns before its
      awaited work finishes and the late `emit` throws "emit was called after
      an event handler completed normally". A handler declared elsewhere (a
      part file, a mixin) cannot be placed and is not judged. `.on<T>(` on
      another object, and comments and strings, never match.

  R19 Runtime diagnostics go through DynamicLogger  (RULE-65)
      No `print(`, `debugPrint(` or `debugPrintStack(` call in lib/ of any
      platform/ or modules/ package or of an app (apps/<id>/lib; comments and
      strings blanked, so a doc example does not count; a method merely
      *named* print is not a call). Use `DynamicLogger.log`. Tests are not
      scanned, and tools/ have their own rule: they write with
      stdout.writeln / stderr.writeln.

  R20 No raw numeric literals for layout and paint  (RULE-30, RULE-33)
      In lib/ of every platform/ and modules/ package and of every app
      (apps/<id>/lib), outside any styles/ or utils/ folder and generated
      files, a number literal may not be the value of: SizedBox(width:|height:),
      SizedBox.square(dimension:), EdgeInsets.all/symmetric/only/fromLTRB (and
      the Directional forms), BorderRadius.circular(, Radius.circular(,
      Radius.elliptical(, Size(, Size.square(, Rect.fromLTWH(, fontSize:,
      blurRadius:, spreadRadius:, strokeWidth: or `.strokeWidth =`; nor the
      size/width/height/radius/thickness/offset arguments of the known
      widgets Container, AnimatedContainer, BoxConstraints (min/max
      width/height), Icon (size), IconButton (iconSize, splashRadius),
      Positioned / PositionedDirectional (top, left, right, bottom, start, end,
      width, height), BorderSide and Border.all (width), Divider and
      VerticalDivider (height, width, thickness, indent), CircleAvatar
      (radius), Image and SvgPicture (width, height), LinearProgressIndicator
      (minHeight). `Offset(x, y)` is flagged only for an argument above 1: a
      fraction (`Offset(0, 1)` for a slide, `Offset(.5, .5)`) is not a pixel
      distance. Take it from `context.w/h/sp/r` or a design token;
      `context.w(16)` is fine, `0` is fine, `16` is not. Constants belong in
      styles/ (tokens) or utils/. Blocking: the tree has none.
      A PARTIAL check, by design: a lexical scan of the constructors above, not
      a type check. A raw double reached through a variable
      (`final w = 100.0; Container(width: w)`) or a widget not listed (a data
      class with a `width` field is deliberately not one) is a review matter.

  R12, R13, R15 and R17-R20 read every file in the working tree that git does not
  ignore (tracked files and new ones about to be added; modules checked out
  as submodules included). Outside a git checkout every file is read.

EXCLUDED FROM SCANNING
  Generated output, one definition for every rule: a file named *.g.dart,
  *.freezed.dart, *.config.dart, *.module.dart, *.gr.dart, *.mocks.dart or
  generated_plugin_registrant.dart, or sitting under a gen/ or generated/
  folder of its package, AND carrying the generator's header in its leading
  comment (`GENERATED CODE`, `generated by`, `dart format width`, ...). gen-l10n
  writes no header, so the output-dir named in a package's l10n.yaml counts
  too; firebase_options_*.dart (FlutterFire output, gitignored) is skipped by
  name. A hand-written lookalike is NOT skipped — it is scanned by every rule,
  and R6 reports it. Folders are read below the package, never the checkout's
  absolute path. Never walked: .git, .dart_tool, .fvm, .idea, .symlinks,
  .pub-cache, build, coverage, ephemeral, node_modules, Pods.
''');
}
