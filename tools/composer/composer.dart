import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../shared/workspace.dart';
import '../unused_checker/output_formatter.dart';

/// Composes an app from its `app_manifest.yaml`.
///
/// Three artifacts in this repository were hand-maintained and had to agree
/// with each other: the root `workspace:` list, an app's path dependencies, and
/// its `injection.dart`. Adding or removing a module meant editing all three in
/// step, and the failure mode for getting it wrong is a boot-time crash that
/// `flutter analyze` cannot see.
///
/// This generates all three from one declaration, between marker comments, so
/// everything outside the markers stays hand-written.
///
/// Packages are resolved by **name**, discovered by scanning for
/// `pubspec.yaml`. No directory layout is encoded here, so moving packages
/// around needs no change to this tool or to any manifest.
///
/// ```
/// dart tools/composer/composer.dart sync [--app <id>] [--strict]
/// dart tools/composer/composer.dart verify
/// dart tools/composer/composer.dart list
/// ```
///
/// `sync` skips a module that is not on disk and says so loudly; `--strict`
/// makes that an error. CI runs `--strict`, which is what stops a release
/// silently shipping without a module someone forgot to check out.

/// Marker pair delimiting a generated region. Regions are **named** because
/// `injection.dart` needs two of them: Dart requires every import before any
/// declaration, so the generated imports and the generated `const` lists
/// cannot sit in one contiguous block.
String _beginMarker(String region) =>
    'composer:managed:$region — generated from app_manifest.yaml';
String _endMarker(String region) => 'composer:end:$region';

void main(List<String> args) {
  if (args.isEmpty || args.contains('--help') || args.contains('-h')) {
    _printHelp(args.isEmpty ? stderr : stdout);
    exit(args.isEmpty ? 1 : 0);
  }

  final command = args.first;
  if (!const {'list', 'sync', 'verify'}.contains(command)) {
    OutputFormatter.printError('Unknown command `$command`.');
    _printHelp(stderr);
    exit(64);
  }

  // Every argument after the command must be one this tool knows. An
  // unknown flag used to be ignored, so `sync --stritc` ran a lenient sync.
  var strict = false;
  String? appFilter;
  for (var i = 1; i < args.length; i++) {
    switch (args[i]) {
      case '--strict':
        strict = true;
      case '--app':
        if (i + 1 >= args.length || args[i + 1].startsWith('-')) {
          OutputFormatter.printError('`--app` needs an app id.');
          exit(64);
        }
        appFilter = args[++i];
      default:
        OutputFormatter.printError('Unknown argument `${args[i]}`.');
        _printHelp(stderr);
        exit(64);
    }
  }

  final root = p.posix.normalize(
    Directory.current.path.replaceAll(r'\', '/'),
  );

  try {
    _run(command, root, appFilter, strict);
  } on YamlException catch (e) {
    // A pubspec or manifest that is not valid YAML — a duplicate key is the
    // usual one. A pubspec, pub rejects too, so nothing resolves until it is
    // fixed; a manifest only composer reads, so that claim is left off.
    final source = e.span == null
        ? null
        : _relativeSource(e.span!.sourceUrl, root);
    final where = source == null ? '' : '$source:${e.span!.start.line + 1}: ';
    final isPubspec =
        source == null || p.posix.basename(source) == 'pubspec.yaml';
    OutputFormatter.printError(
      'Refusing to compose: ${where}not valid YAML — ${_trimDot(e.message)}.'
      '${isPubspec ? ' Pub rejects this file as well, so nothing in the '
                'workspace resolves until it is fixed.' : ' Nothing was written.'}',
    );
    exit(1);
  }
}

void _run(String command, String root, String? appFilter, bool strict) {
  final packages = _discoverPackages(root);
  final apps = _discoverApps(root);

  if (apps.isEmpty) {
    OutputFormatter.printError(
      'No app_manifest.yaml found. Run this from the repository root.',
    );
    exit(1);
  }

  // Before anything else reports on the tree: a pubspec that pub will not
  // parse makes every other result moot. An app pubspec that lists a managed
  // package by hand as well gets the specific refusal from `_sync`.
  if (_invalidYaml.isNotEmpty && command == 'list') {
    _reportInvalidYaml(root);
    exit(1);
  }

  switch (command) {
    case 'list':
      _list(apps, packages, appFilter);
    case 'sync':
      _sync(root, apps, packages, appFilter, strict, dryRun: false);
    case 'verify':
      _sync(root, apps, packages, appFilter, true, dryRun: true);
  }
}

/// Pubspecs that failed to parse during discovery, path -> error.
///
/// Discovery keeps going past them — reading the `name:` line alone — so the
/// check that explains the usual cause (a package declared both by hand and
/// inside the managed region: a duplicate key) still gets to run.
final Map<String, YamlException> _invalidYaml = {};

void _reportInvalidYaml(String root) {
  for (final entry in _invalidYaml.entries) {
    final e = entry.value;
    final line = e.span == null ? '' : ':${e.span!.start.line + 1}';
    OutputFormatter.printError(
      'Refusing to compose: ${p.posix.relative(entry.key, from: root)}$line '
      'is not valid YAML — ${_trimDot(e.message)}. Pub rejects it as well, so nothing '
      'in the workspace resolves until it is fixed.',
    );
  }
}

/// `Duplicate mapping key.` -> `Duplicate mapping key`, so the sentence it
/// is dropped into does not end in `..`.
String _trimDot(String message) => message.replaceFirst(RegExp(r'\.+$'), '');

String _relativeSource(Uri? source, String root) {
  if (source == null) return '<unknown>';
  final path = source.scheme == 'file'
      ? source.toFilePath().replaceAll(r'\', '/')
      : source.toString();
  return p.posix.isAbsolute(path) ? p.posix.relative(path, from: root) : path;
}

/// `loadYaml` with the file's path attached, so a parse error can name it.
dynamic _loadYamlFile(String path) => loadYaml(
  File(path).readAsStringSync(),
  sourceUrl: Uri.file(p.absolute(path)),
);

// ---------------------------------------------------------------------------
// Discovery
// ---------------------------------------------------------------------------

/// Package name -> directory, for every `pubspec.yaml` in the tree.
Map<String, String> _discoverPackages(String root) {
  final out = <String, String>{};
  for (final file in findPubspecs(root)) {
    final path = p.posix.normalize(file.path.replaceAll(r'\', '/'));
    Object? pkg;
    try {
      final doc = _loadYamlFile(path);
      if (doc is! YamlMap) continue;
      pkg = doc['name'];
    } on YamlException catch (error) {
      _invalidYaml[path] = error;
      pkg = RegExp(
        r'^name:\s*([A-Za-z_]\w*)\s*$',
        multiLine: true,
      ).firstMatch(file.readAsStringSync())?.group(1);
    }
    if (pkg is! String) continue;
    out[pkg] = p.posix.dirname(path);
  }
  return out;
}

/// Every workspace member [seeds] reaches through `dependencies` and
/// `dev_dependencies`, seeds included.
///
/// A workspace member must be listed in the root `workspace:` list, and a
/// feature package pulls in core packages (`core_responsive`, `core_ui_kit`,
/// `platform_kernel`, ...) that register no DI module, so no manifest group
/// names them. Walking the pubspecs finds them instead: a manifest names only
/// what the app composes, and the workspace still gets everything that needs
/// to resolve. Dev dependencies count because pub resolves them for every
/// member too.
Set<String> _closure(Iterable<String> seeds, Map<String, String> packages) {
  final out = <String>{};
  final pending = [...seeds];
  while (pending.isNotEmpty) {
    final pkg = pending.removeLast();
    if (!out.add(pkg)) continue;
    final dir = packages[pkg];
    if (dir == null) continue;
    final path = p.posix.join(dir, 'pubspec.yaml');
    if (_invalidYaml.containsKey(path)) continue; // reported by the caller
    final doc = _loadYamlFile(path);
    if (doc is! YamlMap) continue;
    for (final section in const ['dependencies', 'dev_dependencies']) {
      final deps = doc[section];
      if (deps is! YamlMap) continue;
      for (final name in deps.keys.cast<String>()) {
        if (packages.containsKey(name) && !out.contains(name)) {
          pending.add(name);
        }
      }
    }
  }
  return out;
}

/// One `di_groups` entry of a manifest, validated.
class DiGroup {
  const DiGroup(this.name, this.phase, this.packages, this.fromModules);

  final String name;

  /// `before` or `after` — nothing else ([_parseManifest] refuses it).
  final String phase;
  final List<String> packages;

  /// The module layer this group collects, if any.
  final String? fromModules;
}

/// One `modules` entry of a manifest, validated.
class ModuleRef {
  const ModuleRef(this.id, this.layers);

  final String id;
  final List<String> layers;
}

/// An `app_manifest.yaml`, read into typed fields by [_parseManifest].
///
/// Nothing downstream reads the raw YAML: every shape the generators rely on
/// is checked once, up front, so a malformed manifest is a named refusal
/// rather than a cast error — or, worse, a clean exit with modules dropped.
class AppManifest {
  AppManifest({
    required this.id,
    required this.kind,
    required this.dir,
    required this.groups,
    required this.modules,
    required this.extraDependencies,
  });

  final String id;
  final String kind;
  final String dir;
  final List<DiGroup> groups;
  final List<ModuleRef> modules;
  final List<String> extraDependencies;
}

/// Every `app_manifest.yaml` under [root], validated, sorted by id.
///
/// Refuses — exit 1, every problem named as `<file>: <key>: <problem>` — when
/// any manifest is malformed or two share an app id. Runs before any command,
/// so nothing is listed or written from a manifest that does not say what it
/// was meant to.
List<AppManifest> _discoverApps(String root) {
  final out = <AppManifest>[];
  final problems = <String>[];
  final idOwner = <String, String>{};
  final paths = [
    for (final file in findAppManifests(root))
      p.posix.normalize(file.path.replaceAll(r'\', '/')),
  ];
  // Directory listing order is filesystem-dependent; sorting the paths makes
  // "which manifest is the duplicate" the same answer on every machine.
  paths.sort();
  for (final path in paths) {
    final rel = p.posix.relative(path, from: root);
    final app = _parseManifest(
      _loadYamlFile(path),
      rel,
      p.posix.dirname(path),
      problems,
    );
    if (app == null) continue;
    final other = idOwner[app.id];
    if (other != null) {
      problems.add(
        '$rel: app.id: `${app.id}` is already the id of $other — `--app` '
        'and every generated file are keyed by it, so each app needs its own',
      );
      continue;
    }
    idOwner[app.id] = rel;
    out.add(app);
  }

  if (problems.isNotEmpty) {
    for (final problem in problems) {
      OutputFormatter.printError(problem);
    }
    OutputFormatter.printError(
      'Refusing to compose: ${problems.length} problem(s) in '
      'app_manifest.yaml. Nothing was written.',
    );
    exit(1);
  }

  out.sort((a, b) => a.id.compareTo(b.id));
  return out;
}

const _topLevelKeys = {'app', 'di_groups', 'modules', 'extra_dependencies'};
const _appKeys = {'id', 'kind', 'entrypoint'};
const _groupKeys = {'name', 'phase', 'packages', 'from_modules'};
const _moduleKeys = {'id', 'layers'};
const _phases = ['before', 'after'];
const _layers = ['api', 'domain', 'data', 'feature'];

/// Layers a module may list without any `di_groups` entry collecting them.
///
/// A module's API package (`<id>_api`, `modules/<id>/api`) holds contracts
/// only — interfaces other features implement against, no DI module — so it
/// is not composed into `injection.dart` and the app does not depend on it.
/// Listing it makes it a workspace member (and, under `--strict`, a package
/// that must be on disk). A group may still collect it with
/// `from_modules: api`, should an API package ever register something.
const _workspaceOnlyLayers = {'api'};

/// A Dart package name — what a module id and a package entry must be.
final _packageName = RegExp(r'^[a-z_][a-z0-9_]*$');

/// A group name becomes `_<name>Modules` in `injection.dart`.
final _identifier = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

/// `a string (`x`)`, `a list`, `nothing` — for "expected X, got Y".
String _describe(Object? value) => switch (value) {
  null => 'nothing',
  String() => 'a string (`$value`)',
  bool() => 'a boolean (`$value`)',
  num() => 'a number (`$value`)',
  YamlList() || List() => 'a list',
  YamlMap() || Map() => 'a map',
  _ => 'a ${value.runtimeType}',
};

/// Reads [doc] (manifest [rel], in [dir]) into an [AppManifest], adding one
/// `<rel>: <key>: <problem>` line to [problems] per defect. Returns null when
/// the manifest has any.
///
/// Each check here closes a way a manifest used to be accepted and then
/// mis-generated: a `phase: befor` dropped every core module from
/// `injection.dart`, `layers: [features]` dropped the module, a duplicate id
/// composed a package twice (a duplicate pubspec key, which pub rejects), and
/// the shapes below crashed the tool with a stack trace.
AppManifest? _parseManifest(
  Object? doc,
  String rel,
  String dir,
  List<String> problems,
) {
  final before = problems.length;
  void bad(String key, String problem) => problems.add('$rel: $key: $problem');

  if (doc is! YamlMap) {
    bad(
      '(root)',
      'expected a map with `app`, `di_groups` and `modules`, got '
          '${doc == null ? 'an empty file' : _describe(doc)}',
    );
    return null;
  }

  // An unknown key is refused, not ignored: `module:` for `modules:` would
  // otherwise compose an app with no modules and exit 0.
  for (final key in doc.keys) {
    if (!_topLevelKeys.contains(key)) {
      bad('$key', 'unknown key — expected one of ${_topLevelKeys.join(', ')}');
    }
  }

  /// A required, non-empty string at [map]`[key]`, reported as [path].
  String? requiredString(YamlMap map, String key, String path) {
    final value = map[key];
    if (value is String && value.trim().isNotEmpty) return value;
    bad(path, 'expected a non-empty string, got ${_describe(value)}');
    return null;
  }

  /// An optional list of package names; null (absent or `key:` with nothing
  /// under it) reads as empty.
  List<String> packageList(Object? value, String path) {
    if (value == null) return const [];
    if (value is! YamlList) {
      bad(path, 'expected a list of package names, got ${_describe(value)}');
      return const [];
    }
    final out = <String>[];
    for (var i = 0; i < value.length; i++) {
      final pkg = value[i];
      if (pkg is String && _packageName.hasMatch(pkg)) {
        out.add(pkg);
      } else {
        bad('$path[$i]', 'expected a package name, got ${_describe(pkg)}');
      }
    }
    return out;
  }

  // -- app ------------------------------------------------------------------
  String? id;
  var kind = 'flutter';
  final app = doc['app'];
  if (app is! YamlMap) {
    bad('app', 'expected a map with `id`, got ${_describe(app)}');
  } else {
    for (final key in app.keys) {
      if (!_appKeys.contains(key)) {
        bad('app.$key', 'unknown key — expected one of ${_appKeys.join(', ')}');
      }
    }
    id = requiredString(app, 'id', 'app.id');
    if (app['kind'] != null) {
      kind = requiredString(app, 'kind', 'app.kind') ?? kind;
    }
    if (app['entrypoint'] != null) {
      requiredString(app, 'entrypoint', 'app.entrypoint');
    }
  }

  // Which group already holds each package: a package composed twice is a
  // duplicate key in the app's generated `dependencies:`.
  final packageOwner = <String, String>{};
  void claim(String pkg, String owner, String path) {
    final other = packageOwner[pkg];
    if (other == null) {
      packageOwner[pkg] = owner;
    } else {
      bad(path, '`$pkg` is already composed by $other');
    }
  }

  // -- di_groups -------------------------------------------------------------
  final groups = <DiGroup>[];
  final collected = <String, String>{}; // layer -> group that collects it
  final rawGroups = doc['di_groups'];
  final problemsBeforeGroups = problems.length;
  if (rawGroups is! YamlList || rawGroups.isEmpty) {
    bad(
      'di_groups',
      'expected a non-empty list of groups (`- name: <n>`, `phase: before|'
          'after`), got ${rawGroups is YamlList ? 'an empty list' : _describe(rawGroups)}',
    );
  } else {
    final names = <String>{};
    var sawAfter = false;
    for (var i = 0; i < rawGroups.length; i++) {
      final path = 'di_groups[$i]';
      final g = rawGroups[i];
      if (g is! YamlMap) {
        bad(
          path,
          'expected a map with `name` and `phase`, got ${_describe(g)}',
        );
        continue;
      }
      for (final key in g.keys) {
        if (!_groupKeys.contains(key)) {
          bad(
            '$path.$key',
            'unknown key — expected one of ${_groupKeys.join(', ')}',
          );
        }
      }

      final name = requiredString(g, 'name', '$path.name');
      if (name != null) {
        if (!_identifier.hasMatch(name)) {
          bad(
            '$path.name',
            '`$name` is not a Dart identifier — it becomes `_${name}Modules` '
                'in injection.dart',
          );
        } else if (!names.add(name)) {
          bad('$path.name', '`$name` names another group already');
        }
      }

      // Validated because the generator filters on it: any other value put
      // the group in neither `externalPackageModulesBefore` nor `...After`.
      final phase = g['phase'];
      if (phase is! String || !_phases.contains(phase)) {
        bad(
          '$path.phase',
          'expected `before` or `after`, got ${_describe(phase)}',
        );
      } else if (phase == 'after') {
        sawAfter = true;
      } else if (sawAfter) {
        bad(
          '$path.phase',
          '`before` group listed after an `after` group — injectable runs '
              'every `before` group first, so this order is not the boot order',
        );
      }

      final label = '`${name ?? path}`';
      final pkgs = packageList(g['packages'], '$path.packages');
      for (var j = 0; j < pkgs.length; j++) {
        claim(pkgs[j], 'group $label', '$path.packages[$j]');
      }

      String? from;
      final rawFrom = g['from_modules'];
      if (rawFrom != null) {
        if (rawFrom is! String || !_layers.contains(rawFrom)) {
          bad(
            '$path.from_modules',
            'expected one of ${_layers.join(', ')}, got ${_describe(rawFrom)}',
          );
        } else if (collected.containsKey(rawFrom)) {
          bad(
            '$path.from_modules',
            '`$rawFrom` is already collected by group ${collected[rawFrom]}',
          );
        } else {
          from = rawFrom;
          collected[rawFrom] = label;
        }
      }

      final rawPkgs = g['packages'];
      if (rawFrom == null &&
          (rawPkgs == null || (rawPkgs is YamlList && rawPkgs.isEmpty))) {
        bad(
          path,
          'names no `packages` and no `from_modules`, so it composes nothing',
        );
      }

      if (name != null && phase is String) {
        groups.add(DiGroup(name, phase, pkgs, from));
      }
    }
  }

  // A layer no group collects is checked only when `di_groups` read cleanly;
  // otherwise every module would repeat the group's own problem.
  final groupsOk = problems.length == problemsBeforeGroups;

  // -- modules ---------------------------------------------------------------
  final modules = <ModuleRef>[];
  final rawModules = doc['modules'];
  if (rawModules != null && rawModules is! YamlList) {
    bad(
      'modules',
      'expected a list of `{ id: <name>, layers: [...] }`, got '
          '${_describe(rawModules)}',
    );
  } else if (rawModules is YamlList) {
    final ids = <String>{};
    for (var i = 0; i < rawModules.length; i++) {
      final path = 'modules[$i]';
      final m = rawModules[i];
      if (m is! YamlMap) {
        bad(
          path,
          'expected `{ id: <name>, layers: [${_layers.join(', ')}] }`, got '
          '${_describe(m)}',
        );
        continue;
      }
      for (final key in m.keys) {
        if (!_moduleKeys.contains(key)) {
          bad(
            '$path.$key',
            'unknown key — expected one of ${_moduleKeys.join(', ')}',
          );
        }
      }

      final moduleId = requiredString(m, 'id', '$path.id');
      if (moduleId != null) {
        if (!_packageName.hasMatch(moduleId)) {
          bad(
            '$path.id',
            '`$moduleId` is not a valid package-name segment (lowercase '
                'letters, digits, `_`)',
          );
        } else if (!ids.add(moduleId)) {
          bad('$path.id', 'module `$moduleId` is listed more than once');
        }
      }

      final rawLayers = m['layers'];
      final layers = <String>[];
      if (rawLayers is! YamlList || rawLayers.isEmpty) {
        bad(
          '$path.layers',
          'expected a non-empty list drawn from ${_layers.join(', ')}, got '
              '${rawLayers is YamlList ? 'an empty list' : _describe(rawLayers)}',
        );
      } else {
        for (var j = 0; j < rawLayers.length; j++) {
          final layer = rawLayers[j];
          if (layer is! String || !_layers.contains(layer)) {
            bad(
              '$path.layers[$j]',
              'expected one of ${_layers.join(', ')}, got ${_describe(layer)}',
            );
          } else if (layers.contains(layer)) {
            bad('$path.layers[$j]', '`$layer` is listed more than once');
          } else if (groupsOk &&
              !collected.containsKey(layer) &&
              !_workspaceOnlyLayers.contains(layer)) {
            bad(
              '$path.layers[$j]',
              '`$layer` is not collected by any di_groups entry — add '
                  '`from_modules: $layer` to one, or the layer is dropped',
            );
          } else {
            layers.add(layer);
          }
        }
      }
      if (moduleId != null) modules.add(ModuleRef(moduleId, layers));
    }
  }

  // -- extra_dependencies ------------------------------------------------------
  final extras = packageList(doc['extra_dependencies'], 'extra_dependencies');
  for (var i = 0; i < extras.length; i++) {
    claim(extras[i], '`extra_dependencies`', 'extra_dependencies[$i]');
  }

  if (problems.length != before || id == null) return null;
  return AppManifest(
    id: id,
    kind: kind,
    dir: dir,
    groups: groups,
    modules: modules,
    extraDependencies: extras,
  );
}

// ---------------------------------------------------------------------------
// Resolution
// ---------------------------------------------------------------------------

/// A module's package for [layer], under either naming convention.
///
/// Accepts `domain_auth` (layer-first, today) and `auth_domain` (module-first,
/// where the vertical-slice layout is going), so the relayout does not have to
/// land in the same commit as anything else.
String? _modulePackage(
  Map<String, String> packages,
  String moduleId,
  String layer,
) {
  final pluralised = layer == 'feature' ? 'feature' : layer;
  for (final candidate in ['${pluralised}_$moduleId', '${moduleId}_$layer']) {
    if (packages.containsKey(candidate)) return candidate;
  }
  return null;
}

class Resolved {
  final diGroups = <({String name, String phase, List<String> packages})>[];

  /// Everything the app depends on: its DI groups' packages and extras.
  final allPackages = <String>[];

  /// Module packages of a layer no group collects (an `api` layer): workspace
  /// members, but neither app dependencies nor DI modules.
  final workspaceOnly = <String>[];
  final missing = <String>[];
}

Resolved _resolve(
  AppManifest app,
  Map<String, String> packages,
  List<String> warnings,
) {
  final r = Resolved();

  List<String> fromModules(String layer) {
    final out = <String>[];
    for (final m in app.modules) {
      if (!m.layers.contains(layer)) continue;
      final pkg = _modulePackage(packages, m.id, layer);
      if (pkg == null) {
        r.missing.add('${m.id}/$layer');
        continue;
      }
      out.add(pkg);
    }
    return out;
  }

  for (final g in app.groups) {
    final explicit = g.packages.where((pkg) {
      if (packages.containsKey(pkg)) return true;
      r.missing.add(pkg);
      return false;
    }).toList();
    final derived = g.fromModules == null
        ? const <String>[]
        : fromModules(g.fromModules!);
    final all = [...explicit, ...derived];
    if (all.isEmpty) continue;
    r.diGroups.add((name: g.name, phase: g.phase, packages: all));
    r.allPackages.addAll(all);
  }

  for (final pkg in app.extraDependencies) {
    if (packages.containsKey(pkg)) {
      r.allPackages.add(pkg);
    } else {
      r.missing.add(pkg);
    }
  }

  final collected = {
    for (final g in app.groups)
      if (g.fromModules != null) g.fromModules!,
  };
  for (final layer in _workspaceOnlyLayers) {
    if (!collected.contains(layer)) r.workspaceOnly.addAll(fromModules(layer));
  }

  for (final m in r.missing) {
    warnings.add('`$m` is declared by ${app.id} but not present on disk');
  }
  return r;
}

// ---------------------------------------------------------------------------
// Generation
// ---------------------------------------------------------------------------

/// `feature_auth` -> `FeatureAuthPackageModule`.
String _moduleClass(String packageName) {
  final pascal = packageName
      .split('_')
      .where((s) => s.isNotEmpty)
      .map((s) => s[0].toUpperCase() + s.substring(1))
      .join();
  return '${pascal}PackageModule';
}

/// True when the package declares `@InjectableInit.microPackage`.
///
/// Checked rather than assumed: `platform_kernel` has no DI module, and naming
/// it in `injection.dart` would be a compile error.
///
/// Matched **without** the parentheses on purpose. A package may pass
/// arguments — `core_notifications` declares
/// `@InjectableInit.microPackage(ignoreUnregisteredTypesInPackages:
/// ['firebase_core'])`, because the app registers `FirebaseOptions` — and an
/// exact `...()` match would silently drop it, the kind of omission that only
/// shows up at boot.
bool _hasDiModule(String packageDir) {
  final f = File(p.posix.join(packageDir, 'lib', 'di', 'module.dart'));
  return f.existsSync() &&
      f.readAsStringSync().contains('@InjectableInit.microPackage');
}

/// Replaces the region between the marker comments, keeping everything else.
///
/// Returns null when the markers are absent, so a caller can report that
/// instead of silently overwriting a hand-written file.
String? _replaceManaged(
  String content,
  String comment,
  String region,
  String body,
) {
  // Line-based, not offset-based: the markers carry their own indentation
  // (two spaces inside a YAML block, none in Dart) and splicing by string
  // offset silently ate it.
  final begin = '$comment ${_beginMarker(region)}';
  final end = '$comment ${_endMarker(region)}';
  final lines = content.split('\n');
  final i = lines.indexWhere((l) => l.contains(begin));
  final j = lines.indexWhere((l) => l.contains(end));
  if (i == -1 || j == -1 || j < i) return null;

  final bodyLines = body.split('\n');
  if (bodyLines.isNotEmpty && bodyLines.last.isEmpty) bodyLines.removeLast();
  return [
    ...lines.sublist(0, i + 1),
    ...bodyLines,
    ...lines.sublist(j),
  ].join('\n');
}

String _workspaceBody(List<String> dirs) => dirs.map((d) => '  - $d\n').join();

String _appDepsBody(
  List<String> pkgs,
  Map<String, String> packages,
  String appDir,
) {
  final buf = StringBuffer();
  for (final pkg in pkgs) {
    final rel = p.posix.relative(packages[pkg]!, from: appDir);
    buf.writeln('  $pkg:');
    buf.writeln('    path: $rel');
  }
  return buf.toString();
}

({String imports, String modules}) _injectionParts(
  Resolved r,
  Map<String, String> packages,
) {
  final withDi = <String, List<String>>{};
  for (final g in r.diGroups) {
    final list = g.packages
        .where((pkg) => _hasDiModule(packages[pkg]!))
        .toList();
    if (list.isNotEmpty) withDi[g.name] = list;
  }

  // The whole `package:` block is generated, fixed imports included. Emitting
  // only the module imports would interleave them with hand-written ones and
  // break `directives_ordering`, which requires one sorted block.
  final imports = <String>[
    "import 'package:core_common/core_common.dart';",
    "import 'package:injectable/injectable.dart';",
  ];
  for (final list in withDi.values) {
    for (final pkg in list) {
      // `core_common.dart`, imported above, already re-exports its own
      // `di/module.module.dart`; importing it again is an
      // `unnecessary_import`, which `flutter analyze` fails on.
      if (pkg == 'core_common') continue;
      imports.add("import 'package:$pkg/di/module.module.dart';");
    }
  }
  imports.sort();
  imports.add('');
  imports.add("import 'injection.config.dart';");

  final buf = StringBuffer();
  for (final g in r.diGroups) {
    final list = withDi[g.name];
    if (list == null) continue;
    buf.writeln('const _${g.name}Modules = [');
    for (final pkg in list) {
      buf.writeln('  ExternalModule(${_moduleClass(pkg)}),');
    }
    buf.writeln('];');
    buf.writeln();
  }

  final before = r.diGroups
      .where((g) => g.phase == 'before' && withDi.containsKey(g.name))
      .map((g) => '..._${g.name}Modules')
      .join(', ');
  final after = r.diGroups
      .where((g) => g.phase == 'after' && withDi.containsKey(g.name))
      .map((g) => '  ..._${g.name}Modules,')
      .join('\n');

  buf.writeln('const _externalModulesBefore = [$before];');
  buf.writeln('const _externalModulesAfter = [\n$after\n];');
  // Both regions are emitted exactly as `dart format` would leave them —
  // two-space list indent, a blank line after the last import — so a format
  // pass over the app cannot put the file out of step with `composer verify`.
  return (imports: '${imports.join('\n')}\n\n', modules: buf.toString());
}

// ---------------------------------------------------------------------------
// Commands
// ---------------------------------------------------------------------------

void _list(
  List<AppManifest> apps,
  Map<String, String> packages,
  String? appFilter,
) {
  final selected = appFilter == null
      ? apps
      : apps.where((a) => a.id == appFilter).toList();
  if (selected.isEmpty) {
    OutputFormatter.printError(
      'No app matches `--app $appFilter`. Known: '
      '${apps.map((a) => a.id).join(', ')}.',
    );
    exit(1);
  }
  OutputFormatter.printHeader(
    'Composer',
    subtitle: '${selected.length} app(s)',
  );
  for (final app in selected) {
    final warnings = <String>[];
    final r = _resolve(app, packages, warnings);
    stdout.writeln('  ${app.id}  (${app.kind})  ->  ${app.dir}');
    for (final g in r.diGroups) {
      stdout.writeln(
        '    ${g.phase.padRight(6)} ${g.name.padRight(8)} '
        '${g.packages.join(', ')}',
      );
    }
    if (r.workspaceOnly.isNotEmpty) {
      stdout.writeln(
        '    ${'api'.padRight(6)} ${'(no DI)'.padRight(8)} '
        '${r.workspaceOnly.join(', ')}',
      );
    }
    if (r.missing.isNotEmpty) {
      OutputFormatter.printWarning('    missing: ${r.missing.join(', ')}');
    }
    stdout.writeln('');
  }
  stdout.writeln('  ${packages.length} packages discovered.');
}

void _sync(
  String root,
  List<AppManifest> apps,
  Map<String, String> packages,
  String? appFilter,
  bool strict, {
  required bool dryRun,
}) {
  OutputFormatter.printHeader(
    dryRun ? 'Composer — verify' : 'Composer — sync',
    subtitle: 'generated from app_manifest.yaml',
  );

  final selected = appFilter == null
      ? apps
      : apps.where((a) => a.id == appFilter).toList();
  if (selected.isEmpty) {
    OutputFormatter.printError(
      'No app matches `--app $appFilter`. Known: '
      '${apps.map((a) => a.id).join(', ')}.',
    );
    exit(1);
  }

  // The specific refusal first: a managed package also declared by hand is
  // a duplicate key, the usual reason a pubspec stops parsing.
  for (final app in selected) {
    final appPubspec = p.posix.join(app.dir, 'pubspec.yaml');
    _refuseHandDeclared(
      appPubspec,
      _resolve(app, packages, <String>[]).allPackages.toSet(),
      root,
    );
  }
  if (_invalidYaml.isNotEmpty) {
    _reportInvalidYaml(root);
    exit(1);
  }

  final warnings = <String>[];
  // Files whose managed region differs from what the manifest generates:
  // drift under `verify`, and under `sync` the files actually rewritten —
  // what the partial-composition warning names, and nothing else.
  final drift = <String>[];
  final workspace = <String>{};
  // Missing packages across *every* app: the root workspace list is written
  // from all of them, so an app `--app` did not select can still make it
  // partial.
  final missing = <String>{};

  // The root `workspace:` list is shared by every app, so it is the union
  // over *all* of them even when `--app` narrows what else is written. It
  // used to be built from the selected apps only: with two apps,
  // `sync --app admin` would have dropped every package only `mobile` uses
  // from the workspace, and `pub get` would then fail to resolve `mobile`.
  for (final app in apps) {
    workspace.add(p.posix.relative(app.dir, from: root));
    final r = _resolve(app, packages, warnings);
    missing.addAll(r.missing);
    for (final pkg in _closure([
      ...r.allPackages,
      ...r.workspaceOnly,
    ], packages)) {
      workspace.add(p.posix.relative(packages[pkg]!, from: root));
    }
  }
  final missingCount = missing.length;

  // Checked before anything is written: `--strict` failing *after* writing
  // would leave the partial composition on disk it exists to refuse.
  if (missingCount > 0 && strict) {
    for (final w in warnings.toSet()) {
      OutputFormatter.printWarning('  $w');
    }
    OutputFormatter.printError(
      '$missingCount declared package(s) missing from disk. '
      '`--strict` treats that as an error, so a release can never quietly '
      'ship without one.',
    );
    exit(1);
  }

  // Every region this run generates, collected before anything is written
  // so a file or marker that has gone missing is refused up front instead of
  // leaving the other regions rewritten around it.
  final regions = <_Region>[];
  for (final app in selected) {
    final r = _resolve(app, packages, <String>[]);

    final appPubspec = p.posix.join(app.dir, 'pubspec.yaml');
    regions.add(
      _Region(
        appPubspec,
        '#',
        'deps',
        _appDepsBody(r.allPackages, packages, app.dir),
      ),
    );
    final injection = _injectionParts(r, packages);
    final injectionPath = p.posix.join(app.dir, 'lib', 'di', 'injection.dart');
    regions
      ..add(_Region(injectionPath, '//', 'imports', injection.imports))
      ..add(_Region(injectionPath, '//', 'modules', injection.modules));
  }

  // The tooling package is a workspace member but belongs to no app, so no
  // manifest names it. Matched by directory, since its package name
  // (`core_tools`) does not match its folder.
  for (final entry in packages.entries) {
    if (p.posix.basename(entry.value) == 'tools') {
      workspace.add(p.posix.relative(entry.value, from: root));
    }
  }
  final ordered = workspace.toList()..sort();
  final stranded = _strandedPackages(root, packages, workspace);
  regions.add(
    _Region(
      p.posix.join(root, 'pubspec.yaml'),
      '#',
      'workspace',
      _workspaceBody(ordered),
    ),
  );

  // A missing file or marker is drift, not a skip. It used to be a warning
  // followed by "up to date" and exit 0 — so deleting a marker (and then
  // hand-editing what it had guarded) passed CI Gate 0, the one check that
  // exists to stop exactly that.
  final broken = <String>[
    for (final region in regions) ?_regionProblem(region, root),
  ];
  if (broken.isNotEmpty) {
    for (final b in broken.toSet()) {
      OutputFormatter.printError('  $b');
    }
    OutputFormatter.printError(
      '${dryRun ? 'Cannot verify' : 'Nothing was written'}: every generated '
      'region needs its file and its '
      '`composer:managed:<region>` / `composer:end:<region>` marker pair. '
      'Restore them (e.g. `git checkout -- <file>`), then run '
      '`dart tools/composer/composer.dart sync`.',
    );
    exit(1);
  }

  // Grouped by file: `injection.dart` holds two regions, and writing them one
  // at a time reported the file — "wrote" or "out of date" — once for each.
  final byFile = <String, List<_Region>>{};
  for (final region in regions) {
    (byFile[region.path] ??= []).add(region);
  }
  for (final entry in byFile.entries) {
    _write(entry.key, entry.value, dryRun, drift, root);
  }

  for (final w in warnings.toSet()) {
    OutputFormatter.printWarning('  $w');
  }

  if (dryRun) {
    for (final line in stranded) {
      OutputFormatter.printError('  $line');
    }
    if (stranded.isNotEmpty) _explainStranded(OutputFormatter.printError);
    if (drift.isEmpty && stranded.isEmpty) {
      OutputFormatter.printSuccess('Generated artifacts are up to date.');
    } else {
      for (final d in drift) {
        OutputFormatter.printError('  out of date: $d');
      }
      if (drift.isNotEmpty) {
        OutputFormatter.printError(
          'Run `dart tools/composer/composer.dart sync`.',
        );
      }
      exit(1);
    }
  } else {
    for (final line in stranded) {
      OutputFormatter.printWarning('  $line');
    }
    if (stranded.isNotEmpty) _explainStranded(OutputFormatter.printWarning);
    OutputFormatter.printSuccess(
      '${selected.length} app(s) composed, '
      '${ordered.length} workspace members.',
    );
    if (missingCount > 0) {
      _warnPartialComposition(root, selected, missingCount, drift);
    }
  }
}

/// Packages on disk under `modules/` or `platform/` that no app composes —
/// one line each, `<dir> (<name>)`, sorted.
///
/// Dropping a module from every manifest removes it from the root
/// `workspace:` list, but its directory stays. `flutter analyze` from the
/// root still reads it, and Gate 3 still runs its tests, against a package
/// pub no longer resolves — failing with errors that never name the cause.
List<String> _strandedPackages(
  String root,
  Map<String, String> packages,
  Set<String> workspace,
) {
  final out = <String>[
    for (final entry in packages.entries)
      if (p.posix.relative(entry.value, from: root) case final dir
          when (dir.startsWith('modules/') || dir.startsWith('platform/')) &&
              !workspace.contains(dir))
        '$dir (${entry.key}) is on disk but in no app\'s composition',
  ];
  return out..sort();
}

/// The fix for [_strandedPackages], printed once after the list.
void _explainStranded(void Function(String) print) => print(
  'A package left on disk outside the workspace breaks `flutter analyze` and '
  'Gate 3 with errors that do not name it. Delete it (the module\'s '
  '`modules/<id>/<layer>`, or the platform package), or re-add it: a module '
  'layer to an app_manifest.yaml `layers:` list, a platform package to a DI '
  'group or to what an app depends on — then run '
  '`dart tools/composer/composer.dart sync`.',
);

/// Says, loudly, that the files just written describe a *partial* workspace.
///
/// This is the expected state while working on one module in a submodule
/// checkout — and it edits three files that are committed. Committing them
/// would drop everyone else's modules from the app. CI catches it (Gate 0
/// regenerates from the manifest, where every module *is* present, and fails
/// on the difference), but finding out in CI is worse than being told here,
/// with the command to undo it.
void _warnPartialComposition(
  String root,
  List<AppManifest> selected,
  int missingCount,
  List<String> written,
) {
  // Only what this run rewrote. Listing every candidate — byte-identical
  // ones included — told people to `git checkout` files that had not changed.
  final touched = written.toSet().toList();

  stdout.writeln('');
  OutputFormatter.printWarning(
    'PARTIAL COMPOSITION — $missingCount declared package(s) are not on disk.',
  );
  stdout.writeln(
    '  What was just written composes only what is present, which is exactly '
    'right\n'
    '  for working on one module. It is wrong to commit: it would drop the '
    'other\n'
    '  modules from the app for everyone.\n',
  );
  if (touched.isEmpty) {
    stdout.writeln(
      '  Files changed by this run: none — they already held this partial\n'
      '  composition. `git status` shows whether an earlier sync left it there.\n',
    );
    return;
  }
  stdout.writeln('  Files changed:');
  for (final t in touched) {
    stdout.writeln('    $t');
  }
  stdout.writeln('\n  Restore them before you commit:');
  stdout.writeln('    git checkout -- ${touched.join(' ')}\n');
}

/// Exits with the specific refusal when [pubspecPath] declares a package of
/// [managed] by hand as well — see [_declaredOutsideManaged].
void _refuseHandDeclared(
  String pubspecPath,
  Set<String> managed,
  String root,
) {
  final clashes = _declaredOutsideManaged(pubspecPath, managed);
  if (clashes.isEmpty) return;
  OutputFormatter.printError(
    '${p.posix.relative(pubspecPath, from: root)} declares '
    '${clashes.join(', ')} by hand as well as inside the '
    '`composer:managed:deps` region. Pub rejects a duplicate key, so '
    'nothing in the workspace resolves. Delete the hand-written entry — '
    'the manifest owns it.',
  );
  exit(1);
}

/// Packages [managed] that [pubspecPath] also declares *outside* the managed
/// region, under `dependencies:` or `dev_dependencies:`.
///
/// Exists because composer once produced exactly this: `extra_dependencies`
/// put `core_responsive` into the generated block while the hand-written
/// block below still had it. YAML parsers disagree about duplicate keys —
/// several keep the last one silently — but pub rejects them, so the whole
/// workspace stopped resolving while every check written against a lenient
/// parser still read clean.
List<String> _declaredOutsideManaged(String pubspecPath, Set<String> managed) {
  final file = File(pubspecPath);
  if (!file.existsSync()) return const [];

  final top = RegExp(r'^([A-Za-z_]\w*):');
  final dep = RegExp(r'^  ([a-z_][a-z0-9_]*):');
  final clashes = <String>{};
  var section = '';
  var inManaged = false;

  for (final line in file.readAsLinesSync()) {
    if (line.contains('composer:managed:deps')) {
      inManaged = true;
      continue;
    }
    if (line.contains('composer:end:deps')) {
      inManaged = false;
      continue;
    }
    if (inManaged) continue;

    final t = top.firstMatch(line);
    if (t != null) {
      section = t.group(1)!;
      continue;
    }
    if (section != 'dependencies' && section != 'dev_dependencies') continue;
    final d = dep.firstMatch(line);
    if (d != null && managed.contains(d.group(1))) clashes.add(d.group(1)!);
  }
  return clashes.toList()..sort();
}

/// One generated region: the file, its comment syntax and the region name.
class _Region {
  const _Region(this.path, this.comment, this.region, this.body);

  final String path;
  final String comment;
  final String region;
  final String body;
}

/// Why [region] cannot be generated — the file or a marker is missing — or
/// null when it can.
String? _regionProblem(_Region region, String root) {
  final file = File(region.path);
  final rel = p.posix.relative(region.path, from: root);
  if (!file.existsSync()) {
    return '$rel does not exist (needed for the `${region.region}` region)';
  }
  final lines = file.readAsLinesSync();
  final begin = '${region.comment} ${_beginMarker(region.region)}';
  final end = '${region.comment} ${_endMarker(region.region)}';
  final i = lines.indexWhere((l) => l.contains(begin));
  final j = lines.indexWhere((l) => l.contains(end));
  if (i == -1) return '$rel has no `$begin` marker';
  if (j == -1) return '$rel has no `$end` marker';
  if (j < i) return '$rel has `$end` before `$begin`';
  return null;
}

/// Applies every region of the file at [path] in one pass, and writes and
/// reports the file at most once.
void _write(
  String path,
  List<_Region> regions,
  bool dryRun,
  List<String> drift,
  String root,
) {
  final file = File(path);
  final rel = p.posix.relative(path, from: root);
  final current = file.readAsStringSync();
  var updated = current;
  for (final region in regions) {
    final next = _replaceManaged(
      updated,
      region.comment,
      region.region,
      region.body,
    );
    // [_regionProblem] vetted every region before the first write.
    if (next == null) {
      throw StateError('$rel lost its `${region.region}` markers mid-run');
    }
    updated = next;
  }
  if (updated == current) return;
  drift.add(rel);
  if (!dryRun) {
    file.writeAsStringSync(updated);
    stdout.writeln('    wrote $rel');
  }
}

void _printHelp([IOSink? sink]) {
  (sink ?? stdout).writeln('''
Composer — generates an app's composition from `app_manifest.yaml`.

USAGE
  dart tools/composer/composer.dart <command> [options]

COMMANDS
  list              Show every app, its DI groups and anything missing.
  sync              Regenerate the managed regions of:
                      - the root pubspec.yaml `workspace:` list
                      - each app's path dependencies
                      - each app's lib/di/injection.dart
                    Writes nothing and exits 1 if any of those files, or a
                    region's composer:managed / composer:end marker, is
                    missing.
  verify            Same resolution, writes nothing; exits 1 on drift — a
                    missing file or marker counts as drift — and on a package
                    under modules/ or platform/ that no app composes (sync
                    only warns about one). Also implies --strict. Use in CI.

OPTIONS
  --app <id>        Only this app (list, sync, verify). The root `workspace:`
                    list is still computed from every app.
  --strict          A module declared in a manifest but absent from disk is an
                    error instead of a warning. CI runs with this, so a release
                    can never silently ship without a module.

MODULE LAYERS
  `modules: - { id: <m>, layers: [api, domain, data, feature] }`. `domain`,
  `data` and `feature` need a di_groups entry with `from_modules: <layer>`.
  `api` (the module's `<m>_api` contracts package) needs none: it becomes a
  workspace member only — no app dependency, no injection.dart entry.

WHY
  The root workspace list, an app's dependencies and its injection.dart all had
  to agree, and were maintained by hand. Getting them out of step fails at boot
  with "<Type> is not registered" — something `flutter analyze` cannot see.

  Only the region between the `composer:managed` and `composer:end` markers is
  generated. Everything else in those files stays hand-written.
''');
}
