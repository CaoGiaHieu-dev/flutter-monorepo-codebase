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

/// The one file in an app that is allowed to name the modules it composes.
///
/// Matched by basename rather than path so it keeps working wherever apps
/// live. Injectable generates `injection.config.dart` beside it, which
/// `isGeneratedSource` already skips.
const _compositionRoot = 'injection.dart';

/// A package belonging to a product module rather than to the platform.
///
/// Derived from the name, like [_layerOf], so moving packages changes nothing
/// here. `domain_core` and `data_core` are layer foundations that live under
/// `platform/` and every app may depend on them directly; the check is for a
/// *named product* module. A module's API package (`<module>_api`) counts:
/// it is removed with its module unless something still imports it.
bool _isModulePackage(String packageName) =>
    ((packageName.startsWith('domain_') ||
            packageName.startsWith('data_') ||
            packageName.startsWith('feature_')) &&
        packageName != 'domain_core' &&
        packageName != 'data_core') ||
    _apiPackages.contains(packageName);

/// Every module API package in the workspace: named `<module>_api` **and**
/// living under `modules/` (`modules/<module>/api`).
///
/// Both conditions, because the suffix alone is not a reliable signal for an
/// import target — pub.dev is full of `*_api` packages — while a workspace
/// package under `modules/` is one of ours. Filled in by [main] before any
/// rule runs.
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
  'flutter_localizations',
  'flutter_web_plugins',
  'material_ui',
  'cupertino_ui',
  'go_router',
  'provider',
  'flutter_bloc',
};

/// Why a pure-Dart package (the domain, the kernel) may not use [dep] — null
/// when it may. [flutter] is asked about packages that are not named in
/// [_flutterBound] or [_transportPackages]: a Flutter plugin, or a package
/// that depends on the Flutter SDK, is as unusable on a Dart VM as the SDK.
String? _pureDartProblem(String dep, _FlutterClosure flutter) {
  if (_transportPackages.contains(dep))
    return 'a transport or persistence package';
  if (_flutterBound.contains(dep)) return 'Flutter or a Flutter-bound package';
  final culprit = flutter.culprit(dep);
  if (culprit != null) {
    return culprit == dep
        ? 'a Flutter plugin'
        : 'it depends on the Flutter-bound `$culprit`';
  }
  return null;
}

/// Why a domain package (`domain_*`, `domain_core` included) may not depend
/// on [dep] — null when it may. RULE-03: pure Dart, no transport, and no
/// workspace package outside the domain layer — `domain_core` and another
/// module's `domain_*` are the only workspace edges a domain may have. A
/// module API package is refused as well: it is what a *feature* reaches a
/// module through, and a domain depending on one would point inward-out.
String? _domainDependencyProblem(String dep, _FlutterClosure flutter) {
  for (final prefix in const ['core_', 'platform_', 'data_', 'feature_']) {
    if (dep.startsWith(prefix)) return 'a `$prefix*` package';
  }
  if (_apiPackages.contains(dep)) return 'a module API package';
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

/// A `package:` directive found in a source file, with the line it sits on.
class _PackageRef {
  _PackageRef(this.package, this.line);

  final String package;
  final int line;
}

/// Matches `import`/`export` of a `package:` URI.
///
/// `dotAll` matters: a directive wraps across lines when it carries a
/// `show` / `hide` / `as` clause. Without it `.*?;` stops at the newline and
/// the directive is silently missed — the same bug that once made
/// `check_unused_packages.dart` under-report.
final _packageDirective = RegExp(
  r'''^\s*(?:import|export)\s+['"]package:([a-zA-Z0-9_]+)(?:/[^'"]*)?['"].*?;''',
  multiLine: true,
  dotAll: true,
);

/// Public `static const` declaration (i.e. not `_privateName`).
final _publicStaticConst = RegExp(
  r'''^\s*static\s+const\s+(?:[\w<>,\s\?]+\s+)?([A-Za-z]\w*)\s*=''',
  multiLine: true,
);

List<_PackageRef> _packageRefsIn(String content) {
  final refs = <_PackageRef>[];
  for (final m in _packageDirective.allMatches(content)) {
    final line = '\n'.allMatches(content.substring(0, m.start)).length + 1;
    refs.add(_PackageRef(m.group(1)!, line));
  }
  return refs;
}

/// The architectural layer a package belongs to, derived from its **name**.
///
/// Deliberately not from its path. The previous version split the directory on
/// `packages` and returned the next segment, so a package moved anywhere else
/// resolved to the empty string — and R1, R2 and R3 all silently passed for it.
/// A guardrail that turns itself off when files move is worse than no
/// guardrail, because the report still says clean.
///
/// Naming is already enforced (§4), so the name is the more reliable signal,
/// and it survives any relayout.
///
/// The exception to the exception: every package under `platform/` is `core`,
/// whatever its name. `data_core` and `domain_core` carry the `data_` /
/// `domain_` prefix but are platform layers — classified by name they were
/// taken for a product data / domain package, which exempted them from R1.
/// The folder is the one thing that says "platform", and a package that sits
/// there (or stray, directly under it) belongs to the platform.
///
/// The one exception is an app, which is recognised by the marker `composer`
/// uses — an `app_manifest.yaml` beside its pubspec — because app packages
/// are named for the product (`app`, `admin_app`), not for a layer. Matching
/// `app` / `app_*` by name classified a second app called `admin_app` as
/// core: R1 then flagged its composition root and R10 skipped it entirely.
String _layerOf(MonorepoPackage pkg, String root) {
  final name = pkg.name;
  if (File(p.join(pkg.rootPath, 'app_manifest.yaml')).existsSync()) {
    return 'app';
  }
  if (_platformGroupOf(pkg, root) != null) return 'core';
  if (name.startsWith('domain_')) return 'domain';
  if (name.startsWith('data_')) return 'data';
  if (name.startsWith('feature_')) return 'features';
  if (_apiPackages.contains(name)) return 'api';
  if (name == 'core_tools') return 'tools';
  // platform_kernel, core_*, *_state_management: the infrastructure ring.
  return 'core';
}

/// Matches a bare sizing extension — a number or a closing paren followed by
/// `.w`, `.h`, `.sp`, `.r`, `.spMin`, `.dg`, `.dm`.
///
/// `core_responsive` declares no such extension on `num`, so these do not
/// resolve against it. This catches one declared elsewhere, which would
/// type-check while reading a value that never notifies anyone.
///
/// Anchored on the receiver so ordinary members (`rect.width`, `state.hasData`)
/// never match, and the trailing boundary keeps `.hour` or `.round()` out.
final RegExp _bareSizingExtension = RegExp(
  r'[\d)]\.(spMin|sp|dg|dm|w|h|r)\b(?!\s*\()',
);

/// Drops a trailing `//` comment so commented-out or explanatory text does not
/// trip a rule. Naive about `//` inside string literals, which is acceptable
/// here: the cost is a false positive on a line that mentions a URL, and the
/// message points straight at it.
String _stripComment(String line) {
  final i = line.indexOf('//');
  return i == -1 ? line : line.substring(0, i);
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

/// A DI lookup that throws when the type is unregistered.
///
/// `getItOrNull<` and `getAllOrEmpty<` do not match: the literal `getIt<` /
/// `getAll<` requires the `<` immediately after, and those two identifiers
/// carry more characters before theirs.
final _throwingLookup = RegExp(r'\bget(?:It|All)<([A-Z]\w*)>');

/// The module a package belongs to — `auth` for `modules/auth/data` — or
/// `null` for a package outside `modules/`.
///
/// Everything under `modules/` is removable, and a module is removed whole:
/// `remove_sample.dart auth` takes its domain, data and feature packages
/// together. So the module, not the single package, is what owns a contract.
String? _moduleOf(MonorepoPackage pkg) {
  final segments = p.posix.split(pkg.rootPath.replaceAll(r'\', '/'));
  final i = segments.lastIndexOf('modules');
  return (i == -1 || i + 1 >= segments.length) ? null : segments[i + 1];
}

/// R1: whether a platform package may not reach [target] at all — it is on
/// the module side of the ring (a `feature_*`, `data_*`, `domain_*` or
/// `<id>_api` package, by name, or any package living under `modules/`).
/// `domain_core` / `data_core` match by name too: reaching them is the
/// approved-edge list's business, not a free pass.
bool _isUpwardOfPlatform(String target, Map<String, MonorepoPackage> packages) {
  if (target.startsWith('feature_') ||
      target.startsWith('data_') ||
      target.startsWith('domain_') ||
      _apiPackages.contains(target)) {
    return true;
  }
  final pkg = packages[target];
  return pkg != null && _moduleOf(pkg) != null;
}

/// R3: why [pkg] (a feature or a data package) may not depend on [dep], or
/// null when it may. Returns the noun phrase and the way out.
///
/// `Feature -> Domain <- Data`: a feature never reaches another feature or any
/// data package (it uses the other module's `<id>_api`); a data package never
/// reaches a feature, nor another module's data package (module data is
/// private to the module that owns it). A module's API package is open to
/// both — it is the public surface.
(String what, String hint)? _moduleLayerProblem(
  MonorepoPackage pkg,
  String layer,
  String dep,
  Map<String, MonorepoPackage> packages,
) {
  if (dep == pkg.name) return null;
  if (layer == 'features') {
    if (dep.startsWith('feature_')) {
      return (
        'another feature',
        'Depend on that module\'s API package (`modules/<id>/api`, '
            '`<id>_api`) or a core_di contract instead.',
      );
    }
    if (dep.startsWith('data_')) {
      return ('data package', 'Features depend on domain, never on data.');
    }
  }
  if (layer == 'data') {
    if (dep.startsWith('feature_')) {
      return (
        'feature',
        'Data implements domain contracts; it never reaches the UI layer.',
      );
    }
    if (dep.startsWith('data_') && dep != 'data_core') {
      final other = packages[dep];
      final sameModule =
          other != null &&
          _moduleOf(pkg) != null &&
          _moduleOf(pkg) == _moduleOf(other);
      if (!sameModule) {
        return (
          'another module\'s data package',
          'A module\'s data stays private to it: go through its domain '
              'contract or its `<id>_api` package.',
        );
      }
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
      if (isGeneratedSource(file)) continue;
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
  if (_moduleOf(pkg) != null) {
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
    if (pkg.name.endsWith('_api') && _moduleOf(pkg) != null) {
      _apiPackages.add(pkg.name);
    }
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
    for (final pkg in packages.values) ScanUnit(_moduleOf(pkg), pkg.rootPath),
  ], contractTypes);

  // R16 reads the same contracts: a shell lookup that is not in the catalog is
  // a contract no app is asked to decide about.
  blocking.addAll(
    _catalogViolations(root, packages, contractTypes, removableContracts),
  );

  final flutter = _FlutterClosure(root, packages);

  for (final pkg in packages.values) {
    final layer = _layerOf(pkg, root);
    // A domain package is recognised by its name even when it sits under
    // `platform/` (`domain_core`, classified `core`): RULE-03 holds it too.
    final isDomain = pkg.name.startsWith('domain_') && layer != 'app';
    final files = dartFilesUnderLib(pkg.rootPath);
    // Parsed from YAML by MonorepoHelper — a hand-rolled line scanner
    // silently drops entries after a blank line inside the block.
    final declared = pkg.dependencies;

    // --- R1 / R3: forbidden edges, by import ------------------------------
    for (final file in files) {
      if (isGeneratedSource(file)) continue;
      final content = File(file).readAsStringSync();
      final rel = p.posix.relative(file, from: root);

      for (final ref in _packageRefsIn(content)) {
        final target = ref.package;
        final edge = '${pkg.name} -> $target';

        if (layer == 'core' && target != pkg.name) {
          final upward = _isUpwardOfPlatform(target, packages);
          if (upward && !_approvedUpwardEdges.containsKey(edge)) {
            blocking.add(
              Violation(
                'R1',
                '$rel:${ref.line}',
                'core package `${pkg.name}` imports `$target`. '
                    'Core must not depend on an outer ring.',
              ),
            );
          }
        }

        if (layer == 'features' || layer == 'data') {
          final problem = _moduleLayerProblem(pkg, layer, target, packages);
          if (problem != null) {
            blocking.add(
              Violation(
                'R3',
                '$rel:${ref.line}',
                '`${pkg.name}` imports ${problem.$1} `$target`. '
                    '${problem.$2}',
              ),
            );
          }
        }

        // An API package is the public surface of its module: contracts over
        // the foundation and Flutter, nothing else. Importing its own
        // module's domain would leak that module's entities to every
        // consumer; importing any other module would chain removals.
        if (layer == 'api' && target != pkg.name) {
          final problem = _apiDependencyProblem(target, packages, root);
          if (problem != null) {
            blocking.add(
              Violation(
                'R3',
                '$rel:${ref.line}',
                'API package `${pkg.name}` imports `$target` ($problem). '
                    'An API package may depend on the foundation '
                    '(core_di, platform_kernel, core_common) and Flutter only.',
              ),
            );
          }
        }

        if (isDomain) {
          final problem = _domainDependencyProblem(target, flutter);
          if (problem != null) {
            blocking.add(
              Violation(
                'R2',
                '$rel:${ref.line}',
                'domain package `${pkg.name}` imports `$target` ($problem). '
                    'Domain is pure Dart and depends on domain_* packages '
                    'only.',
              ),
            );
          }
        }

        // --- R5: used but not declared ------------------------------------
        final selfOrSdk = target == pkg.name || _sdkPackages.contains(target);
        if (!selfOrSdk && !declared.contains(target)) {
          blocking.add(
            Violation(
              'R5',
              '$rel:${ref.line}',
              '`${pkg.name}` imports `$target` but does not declare it in '
                  '`dependencies:`. Pub Workspaces hide this locally; it '
                  'breaks when the package is extracted.',
            ),
          );
        }
      }
    }

    // --- R1 / R2: forbidden edges, by pubspec -----------------------------
    final pubspecRel = p.posix.relative(
      p.posix.join(pkg.rootPath, 'pubspec.yaml'),
      from: root,
    );

    if (layer == 'core') {
      for (final dep in declared) {
        if (dep == pkg.name) continue;
        final upward = _isUpwardOfPlatform(dep, packages);
        if (upward &&
            !_approvedUpwardEdges.containsKey('${pkg.name} -> $dep')) {
          blocking.add(
            Violation(
              'R1',
              pubspecRel,
              'core package `${pkg.name}` declares `$dep`. '
                  'Add it to _approvedUpwardEdges and RULE-01, or remove it.',
            ),
          );
        }
      }
    }

    if (layer == 'features' || layer == 'data') {
      for (final dep in declared) {
        final problem = _moduleLayerProblem(pkg, layer, dep, packages);
        if (problem == null) continue;
        blocking.add(
          Violation(
            'R3',
            pubspecRel,
            '`${pkg.name}` declares ${problem.$1} `$dep`. ${problem.$2}',
          ),
        );
      }
    }

    if (layer == 'api') {
      for (final dep in declared) {
        if (dep == pkg.name) continue;
        final problem = _apiDependencyProblem(dep, packages, root);
        if (problem == null) continue;
        blocking.add(
          Violation(
            'R3',
            pubspecRel,
            'API package `${pkg.name}` declares `$dep` ($problem). An API '
                'package may depend on the foundation and Flutter only.',
          ),
        );
      }
    }

    // --- R11: platform group direction, by pubspec --------------------------
    // `dependencies:` only. A dev dependency never ships and never reaches a
    // consumer's graph: `platform_app_shell`'s tests use `core_storage` for
    // their fakes, and that is not an edge of the product graph. Imports need
    // no separate pass — R5 already holds every import to `dependencies:`.
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
      for (final dep in declared) {
        final target = packages[dep];
        if (target == null || dep == pkg.name) continue;
        // Every platform group sits below every module: a modules/ package is
        // a target no group may reach (R1 says the same by name).
        if (_moduleOf(target) != null) {
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

    if (isDomain) {
      for (final dep in declared) {
        final problem = _domainDependencyProblem(dep, flutter);
        if (problem == null) continue;
        blocking.add(
          Violation(
            'R2',
            pubspecRel,
            'domain package `${pkg.name}` declares `$dep` under '
                '`dependencies:` ($problem). Domain must resolve without the '
                'Flutter SDK and depend on domain_* packages only.',
          ),
        );
      }
    }

    // --- R4: shared constants belong in utils/ ----------------------------
    for (final file in files) {
      if (isGeneratedSource(file)) continue;
      // Design-token exception: core_base_ui keeps its tokens in styles/,
      // which names the intent better than a generic utils/ bucket.
      if (file.contains('/utils/') || file.contains('/styles/')) continue;

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
    for (final file in files) {
      final source = File(file).readAsStringSync();
      if (!source.contains('core_responsive')) continue;

      final lines = source.split('\n');
      for (var i = 0; i < lines.length; i++) {
        final code = _stripComment(lines[i]);
        // A numeric or closing-paren receiver followed by a sizing extension.
        for (final m in _bareSizingExtension.allMatches(code)) {
          blocking.add(
            Violation(
              'R7',
              '${p.posix.relative(file, from: root)}:${i + 1}',
              'bare `.${m.group(1)}` sizing extension — use '
                  '`context.${m.group(1)}(value)` so the widget rebuilds when '
                  'screen metrics change. If no BuildContext is reachable, '
                  'read the value from one before the first `await` and pass '
                  'it in.',
            ),
          );
        }
      }
    }

    // --- R9: the pure-Dart tier stays pure ---------------------------------
    // Checked in the pubspec as well as the imports. R2 checks imports only,
    // which is how `data_auth` kept a clean bill of health while declaring
    // firebase_auth and google_sign_in — Flutter plugins that cannot run on a
    // Dart VM — without a single `package:flutter` import in its source.
    if (_isPureDartTier(pkg.name)) {
      for (final dep in declared) {
        final problem = _pureDartProblem(dep, flutter);
        if (problem == null) continue;
        blocking.add(
          Violation(
            'R9',
            pubspecRel,
            '`${pkg.name}` is pure-Dart tier but declares `$dep` ($problem). '
                'Move whatever needs it into a Flutter-side package.',
          ),
        );
      }
      for (final file in files) {
        if (isGeneratedSource(file)) continue;
        final content = File(file).readAsStringSync();
        for (final ref in _packageRefsIn(content)) {
          final problem = _pureDartProblem(ref.package, flutter);
          if (problem == null) continue;
          blocking.add(
            Violation(
              'R9',
              '${p.posix.relative(file, from: root)}:${ref.line}',
              '`${pkg.name}` is pure-Dart tier and must not import '
                  '`${ref.package}` ($problem).',
            ),
          );
        }
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
      if (isGeneratedSource(file)) continue;
      final lines = File(file).readAsStringSync().split('\n');
      for (var i = 0; i < lines.length; i++) {
        final code = _stripComment(lines[i]);
        for (final m in _throwingLookup.allMatches(code)) {
          final type = m.group(1)!;
          final owners = removableContracts[type];
          if (owners == null) continue;
          // The owning module may resolve its own contract eagerly: if one
          // of its packages is in the build, so is the registration.
          final module = _moduleOf(pkg);
          if (module != null && owners.contains(module)) continue;

          blocking.add(
            Violation(
              'R8',
              '${p.posix.relative(file, from: root)}:${i + 1}',
              '`$type` is implemented only in modules/${owners.join(', modules/')}, '
                  'which is removable — a throwing lookup here crashes any '
                  'build without it. Use `getItOrNull<$type>()` (or '
                  '`getAllOrEmpty`) and handle the null case.',
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
    // The app's tests are held to the same line: a test that names a module
    // type is a build that stops compiling when the module is removed, and a
    // removed module is exactly what the smoke test exists to prove boots.
    // Only the composition root *in lib/* may name a module.
    if (layer == 'app') {
      final libRoot = p.posix.join(pkg.rootPath, 'lib');
      for (final file in [...files, ..._dartFilesUnder(pkg.rootPath, 'test')]) {
        if (isGeneratedSource(file)) continue;
        final rel = p.posix.relative(file, from: root);
        if (p.posix.basename(file) == _compositionRoot &&
            p.posix.isWithin(libRoot, file)) {
          continue;
        }

        final content = File(file).readAsStringSync();
        for (final ref in _packageRefsIn(content)) {
          if (!_isModulePackage(ref.package)) continue;
          blocking.add(
            Violation(
              'R10',
              '$rel:${ref.line}',
              'the app imports `${ref.package}`. Only '
                  '`lib/**/$_compositionRoot` may name a module (its API package '
                  'included); everywhere else '
                  'declare a contract in `core_di` and resolve it with '
                  '`getItOrNull`. A type import cannot be guarded — it fails '
                  'the build the moment that module is removed.',
            ),
          );
        }
      }
    }

    // --- R6: generated files should not be hand-edited (warning) ----------
    for (final file in files) {
      final name = p.posix.basename(file);
      final isConventional =
          name.endsWith('.g.dart') ||
          name.endsWith('.freezed.dart') ||
          name.endsWith('.config.dart') ||
          name.endsWith('.module.dart');
      if (!isConventional) continue;

      final head = File(file).readAsStringSync();
      final marker = head.length > 400 ? head.substring(0, 400) : head;
      if (!marker.contains('GENERATED CODE') &&
          !marker.contains('dart format width') &&
          !marker.contains('coverage:ignore-file')) {
        warnings.add(
          Violation(
            'R6',
            p.posix.relative(file, from: root),
            'generated file is missing its generator header — it may have '
                'been hand-edited. Re-run `dart run build_runner build '
                '--workspace`.',
          ),
        );
      }
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

/// Generated Dart, excluded from R13 and R15: nobody writes its comments or
/// its class names, and a generator is entitled to its `ignore_for_file`.
bool _isGeneratedForHygiene(String rel) {
  final name = p.posix.basename(rel);
  return name.endsWith('.g.dart') ||
      name.endsWith('.freezed.dart') ||
      name.endsWith('.config.dart') ||
      name.endsWith('.module.dart') ||
      name.endsWith('.gr.dart') ||
      name.endsWith('.mocks.dart') ||
      name == 'generated_plugin_registrant.dart' ||
      name.startsWith('firebase_options_') ||
      rel.contains('lib/src/gen/');
}

/// An analyzer suppression: `// ignore: rule` or `// ignore_for_file: rule`.
/// Matched against the text of a real line comment only (see [DartSource]),
/// so the same words inside a string literal or a `///` doc comment do not
/// count — the analyzer does not honour them there either.
final _suppression = RegExp(r'^//\s*(ignore(?:_for_file)?)\s*:');

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

    if (!rel.endsWith('.dart') || _isGeneratedForHygiene(rel)) continue;

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
          '`// ${m.group(1)}:` suppresses the analyzer. Fix the cause — for '
              'a deprecation, migrate to the replacement API — instead of '
              'silencing it.',
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

RULES CHECKED
  R1  Dependency direction
      No package under platform/ — every group, platform/layers/data
      (data_core) and platform/layers/domain (domain_core) included — may
      import or declare a feature_*, data_*, domain_* or module API (<id>_api)
      package, or any package living under modules/, except for the approved
      edges listed at the top of the run. A platform package is recognised by
      its folder, not by its name. Checked in both lib/ imports and
      pubspec.yaml.

  R2  Domain is pure Dart
      No domain_* package (domain_core included) may import or declare under
      `dependencies:` flutter, material_ui, cupertino_ui, go_router, provider,
      flutter_bloc, dio, retrofit, drift or http, nor any core_*, platform_*,
      data_*, feature_* or module API (<id>_api) package, nor any package that
      is a Flutter plugin or depends on the Flutter SDK (found through the
      pubspecs pub resolved, `.dart_tool/package_config.json`). domain_core and
      other domain_* packages are its only workspace dependencies
      (dev_dependencies are not checked).

  R3  Module layer boundaries (Feature -> Domain <- Data)
      A feature may not import or declare another feature, nor any data_*
      package. A data package may not import or declare a feature_* package,
      nor another module's data_* package (data_core and its own module's are
      fine). Cross-feature work goes through the other module's API package
      (modules/<id>/api, named <id>_api) or a product-neutral contract in
      core_di. An API package (<id>_api under modules/) may depend on
      platform/foundation/ packages and Flutter/pub packages only — never on
      its own module's domain/data/feature, another module's package or API,
      or any other platform group. (A domain package may not use an API
      package either: R2.) Checked in lib/ imports and pubspec.yaml, so a
      dependency declared and never imported fails too.

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

  R6  Generated files are not hand-edited  (warning only, never blocks)
      Files named *.g.dart / *.freezed.dart / *.config.dart / *.module.dart
      should carry their generator header.

  R7  Responsive sizing goes through BuildContext
      `16.w` and `context.w(16)` compute the same number, but only the
      second registers an InheritedWidget dependency, so only the second
      rebuilds when metrics change (rotation, split-screen, resize).
      Checked in files that mention core_responsive (in practice: import it).

  R8  Removable contracts resolve optionally
      A `core_di` contract or a module API type (declared in any <id>_api
      package) implemented only under modules/ (any layer — a data
      package's gateway as much as a feature's navigator) disappears when
      that module is removed. `getIt<T>()` and `getAll<T>()` throw in
      that case, so such a type must be resolved with `getItOrNull<T>()` /
      `getAllOrEmpty<T>()` and a fallback. Packages of the implementing
      module may still resolve its contracts eagerly.
      Invisible to `flutter analyze`: the lookup type-checks, then crashes at
      runtime on whichever screen calls it.

  R9  The pure-Dart tier stays pure
      `platform_kernel` must neither import nor declare in `pubspec.yaml`:
      Flutter and its bound packages (material_ui, cupertino_ui,
      flutter_localizations, flutter_web_plugins, go_router, provider,
      flutter_bloc), the transport and persistence libraries (dio, retrofit,
      drift, http), or any package that is a Flutter plugin or depends on the
      Flutter SDK, directly or through other packages (read from the
      workspace pubspecs and `.dart_tool/package_config.json`). The pubspec
      half matters: a package can declare a Flutter plugin and never write
      `import 'package:flutter/...'`.

  R10 The app shell composes modules, it does not import them
      In an app (a package with app_manifest.yaml), only lib/di/injection.dart
      — the composition root — may import a domain_*, data_*, feature_* or
      <id>_api package. Anywhere else — lib/ and the app's test/ included —
      a module import is an unguardable compile-time dependency: the build
      breaks the moment that module is removed.

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
      No `// ignore: <rule>` or `// ignore_for_file: <rule>` comment in any
      .dart file of the repository (tools/, test/ and apps/ included). Fix
      the cause; for a deprecation, migrate to the replacement API. Only real
      line comments count — the same text inside a string literal or a `///`
      doc comment is not a suppression and is not reported.
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

  R12, R13, R15 and R17 read every file in the working tree that git does not
  ignore (tracked files and new ones about to be added; modules checked out
  as submodules included). Outside a git checkout every file is read.

EXCLUDED FROM SCANNING
  Generated output: *.g.dart, *.freezed.dart, *.config.dart, *.module.dart,
  *.mocks.dart, firebase_options_*.dart, and anything under gen/ or generated/.
  R13 and R15 also skip *.gr.dart, generated_plugin_registrant.dart and
  lib/src/gen/**. Never walked: .git, .dart_tool, .fvm, .idea, .symlinks,
  .pub-cache, build, coverage, ephemeral, node_modules, Pods.
''');
}
