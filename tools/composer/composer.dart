import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

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
    // usual one. Pub rejects it too, so nothing resolves until it is fixed.
    final where = e.span == null
        ? ''
        : '${_relativeSource(e.span!.sourceUrl, root)}:'
              '${e.span!.start.line + 1}: ';
    OutputFormatter.printError(
      'Refusing to compose: ${where}not valid YAML — ${_trimDot(e.message)}. Pub '
      'rejects this file as well, so nothing in the workspace resolves until '
      'it is fixed.',
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
  void walk(Directory dir) {
    for (final e in dir.listSync(followLinks: false)) {
      final name = p.posix.basename(e.path.replaceAll(r'\', '/'));
      if (e is Directory) {
        const skip = {
          '.git',
          '.dart_tool',
          'build',
          'ios',
          'android',
          'macos',
          'windows',
          'linux',
          'web',
        };
        if (skip.contains(name)) continue;
        walk(e);
      } else if (e is File && name == 'pubspec.yaml') {
        final path = p.posix.normalize(e.path.replaceAll(r'\', '/'));
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
          ).firstMatch(e.readAsStringSync())?.group(1);
        }
        if (pkg is! String) continue;
        out[pkg] = p.posix.dirname(path);
      }
    }
  }

  walk(Directory(root));
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

class AppManifest {
  AppManifest(this.id, this.dir, this.doc);

  final String id;
  final String dir;
  final YamlMap doc;

  String get kind => (doc['app'] as YamlMap)['kind'] as String? ?? 'flutter';
}

List<AppManifest> _discoverApps(String root) {
  final out = <AppManifest>[];
  void walk(Directory dir) {
    for (final e in dir.listSync(followLinks: false)) {
      final name = p.posix.basename(e.path.replaceAll(r'\', '/'));
      if (e is Directory) {
        const skip = {'.git', '.dart_tool', 'build', 'packages', 'modules'};
        if (skip.contains(name)) continue;
        walk(e);
      } else if (e is File && name == 'app_manifest.yaml') {
        final doc = _loadYamlFile(e.path) as YamlMap;
        final id = (doc['app'] as YamlMap)['id'] as String;
        out.add(
          AppManifest(
            id,
            p.posix.dirname(p.posix.normalize(e.path.replaceAll(r'\', '/'))),
            doc,
          ),
        );
      }
    }
  }

  walk(Directory(root));
  out.sort((a, b) => a.id.compareTo(b.id));
  return out;
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
  final allPackages = <String>[];
  final missing = <String>[];
}

Resolved _resolve(
  AppManifest app,
  Map<String, String> packages,
  List<String> warnings,
) {
  final r = Resolved();
  final modules = (app.doc['modules'] as YamlList?) ?? YamlList();

  List<String> fromModules(String layer) {
    final out = <String>[];
    for (final m in modules) {
      final id = m['id'] as String;
      final layers = (m['layers'] as YamlList).cast<String>();
      if (!layers.contains(layer)) continue;
      final pkg = _modulePackage(packages, id, layer);
      if (pkg == null) {
        r.missing.add('$id/$layer');
        continue;
      }
      out.add(pkg);
    }
    return out;
  }

  for (final g in (app.doc['di_groups'] as YamlList)) {
    final name = g['name'] as String;
    final phase = g['phase'] as String;
    final explicit = ((g['packages'] as YamlList?) ?? YamlList())
        .cast<String>()
        .where((pkg) {
          if (packages.containsKey(pkg)) return true;
          r.missing.add(pkg);
          return false;
        })
        .toList();
    final derived = g['from_modules'] == null
        ? const <String>[]
        : fromModules(g['from_modules'] as String);
    final all = [...explicit, ...derived];
    if (all.isEmpty) continue;
    r.diGroups.add((name: name, phase: phase, packages: all));
    r.allPackages.addAll(all);
  }

  for (final pkg
      in ((app.doc['extra_dependencies'] as YamlList?) ?? YamlList())
          .cast<String>()) {
    if (packages.containsKey(pkg)) {
      r.allPackages.add(pkg);
    } else {
      r.missing.add(pkg);
    }
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
    for (final pkg in _closure(r.allPackages, packages)) {
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

  for (final app in selected) {
    final r = _resolve(app, packages, <String>[]);

    final appPubspec = p.posix.join(app.dir, 'pubspec.yaml');
    _write(
      appPubspec,
      '#',
      'deps',
      _appDepsBody(r.allPackages, packages, app.dir),
      dryRun,
      drift,
      root,
    );
    final injection = _injectionParts(r, packages);
    final injectionPath = p.posix.join(app.dir, 'lib', 'di', 'injection.dart');
    _write(
      injectionPath,
      '//',
      'imports',
      injection.imports,
      dryRun,
      drift,
      root,
    );
    _write(
      injectionPath,
      '//',
      'modules',
      injection.modules,
      dryRun,
      drift,
      root,
    );
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
  _write(
    p.posix.join(root, 'pubspec.yaml'),
    '#',
    'workspace',
    _workspaceBody(ordered),
    dryRun,
    drift,
    root,
  );

  for (final w in warnings.toSet()) {
    OutputFormatter.printWarning('  $w');
  }

  if (dryRun) {
    if (drift.isEmpty) {
      OutputFormatter.printSuccess('Generated artifacts are up to date.');
    } else {
      for (final d in drift) {
        OutputFormatter.printError('  out of date: $d');
      }
      OutputFormatter.printError(
        'Run `dart tools/composer/composer.dart sync`.',
      );
      exit(1);
    }
  } else {
    OutputFormatter.printSuccess(
      '${selected.length} app(s) composed, '
      '${ordered.length} workspace members.',
    );
    if (missingCount > 0) {
      _warnPartialComposition(root, selected, missingCount, drift);
    }
  }
}

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

void _write(
  String path,
  String comment,
  String region,
  String body,
  bool dryRun,
  List<String> drift,
  String root,
) {
  final file = File(path);
  final rel = p.posix.relative(path, from: root);
  if (!file.existsSync()) {
    OutputFormatter.printWarning('  $rel does not exist — skipped');
    return;
  }
  final current = file.readAsStringSync();
  final updated = _replaceManaged(current, comment, region, body);
  if (updated == null) {
    OutputFormatter.printWarning(
      '  $rel has no `${_beginMarker(region)}` marker — left untouched',
    );
    return;
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
  verify            Same resolution, writes nothing; exits 1 on drift.
                    Also implies --strict. Use in CI.

OPTIONS
  --app <id>        Only this app (list, sync, verify). The root `workspace:`
                    list is still computed from every app.
  --strict          A module declared in a manifest but absent from disk is an
                    error instead of a warning. CI runs with this, so a release
                    can never silently ship without a module.

WHY
  The root workspace list, an app's dependencies and its injection.dart all had
  to agree, and were maintained by hand. Getting them out of step fails at boot
  with "<Type> is not registered" — something `flutter analyze` cannot see.

  Only the region between the `composer:managed` and `composer:end` markers is
  generated. Everything else in those files stays hand-written.
''');
}
