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
    _printHelp();
    exit(args.isEmpty ? 1 : 0);
  }

  final command = args.first;
  final strict = args.contains('--strict');
  final appFilter = _valueOf(args, '--app');
  final root = p.posix.normalize(
    Directory.current.path.replaceAll(r'\', '/'),
  );

  final packages = _discoverPackages(root);
  final apps = _discoverApps(root);

  if (apps.isEmpty) {
    OutputFormatter.printError(
      'No app_manifest.yaml found. Run this from the repository root.',
    );
    exit(1);
  }

  switch (command) {
    case 'list':
      _list(apps, packages);
    case 'sync':
      _sync(root, apps, packages, appFilter, strict, dryRun: false);
    case 'verify':
      _sync(root, apps, packages, appFilter, true, dryRun: true);
    default:
      OutputFormatter.printError('Unknown command `$command`.');
      _printHelp();
      exit(1);
  }
}

String? _valueOf(List<String> args, String flag) {
  final i = args.indexOf(flag);
  return (i == -1 || i + 1 >= args.length) ? null : args[i + 1];
}

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
        final doc = loadYaml(e.readAsStringSync());
        if (doc is! YamlMap) continue;
        final pkg = doc['name'];
        if (pkg is! String) continue;
        out[pkg] = p.posix.dirname(
          p.posix.normalize(e.path.replaceAll(r'\', '/')),
        );
      }
    }
  }

  walk(Directory(root));
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
        final doc = loadYaml(e.readAsStringSync()) as YamlMap;
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

  for (final pkg in ((app.doc['extra_dependencies'] as YamlList?) ?? YamlList())
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
/// Matched **without** the parentheses on purpose. Three packages here pass
/// arguments — `@InjectableInit.microPackage(ignoreUnregisteredTypesInPackages:
/// [...])` — and an exact `...()` match silently dropped all three, which is
/// the kind of omission that only shows up at boot.
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

String _workspaceBody(List<String> dirs) =>
    dirs.map((d) => '  - $d\n').join();

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
      .map((g) => '    ..._${g.name}Modules,')
      .join('\n');

  buf.writeln('const _externalModulesBefore = [$before];');
  buf.writeln('const _externalModulesAfter = [\n$after\n];');
  return (imports: '${imports.join('\n')}\n', modules: buf.toString());
}

// ---------------------------------------------------------------------------
// Commands
// ---------------------------------------------------------------------------

void _list(List<AppManifest> apps, Map<String, String> packages) {
  OutputFormatter.printHeader('Composer', subtitle: '${apps.length} app(s)');
  for (final app in apps) {
    final warnings = <String>[];
    final r = _resolve(app, packages, warnings);
    stdout.writeln('  ${app.id}  (${app.kind})  ->  ${app.dir}');
    for (final g in r.diGroups) {
      stdout.writeln('    ${g.phase.padRight(6)} ${g.name.padRight(8)} '
          '${g.packages.join(', ')}');
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
    OutputFormatter.printError('No app matches `--app $appFilter`.');
    exit(1);
  }

  final warnings = <String>[];
  final drift = <String>[];
  final workspace = <String>{};
  var missingCount = 0;

  for (final app in selected) {
    final r = _resolve(app, packages, warnings);
    missingCount += r.missing.length;

    workspace.add(p.posix.relative(app.dir, from: root));
    for (final pkg in r.allPackages) {
      workspace.add(p.posix.relative(packages[pkg]!, from: root));
    }

    final appPubspec = p.posix.join(app.dir, 'pubspec.yaml');
    final clashes = _declaredOutsideManaged(appPubspec, r.allPackages.toSet());
    if (clashes.isNotEmpty) {
      OutputFormatter.printError(
        '${p.posix.relative(appPubspec, from: root)} declares '
        '${clashes.join(', ')} by hand as well as inside the '
        '`composer:managed:deps` region. Pub rejects a duplicate key, so '
        'nothing in the workspace resolves. Delete the hand-written entry — '
        'the manifest owns it.',
      );
      exit(1);
    }

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
    _write(injectionPath, '//', 'imports', injection.imports, dryRun, drift,
        root);
    _write(injectionPath, '//', 'modules', injection.modules, dryRun, drift,
        root);
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

  for (final w in warnings) {
    OutputFormatter.printWarning('  $w');
  }
  if (missingCount > 0 && strict) {
    OutputFormatter.printError(
      '$missingCount declared package(s) missing from disk. '
      '`--strict` treats that as an error, so a release can never quietly '
      'ship without one.',
    );
    exit(1);
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
      _warnPartialComposition(root, selected, missingCount);
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
) {
  final touched = <String>[p.posix.relative(p.posix.join(root, 'pubspec.yaml'),
      from: root)];
  for (final app in selected) {
    touched.add(p.posix.relative(p.posix.join(app.dir, 'pubspec.yaml'),
        from: root));
    touched.add(p.posix.relative(
        p.posix.join(app.dir, 'lib', 'di', 'injection.dart'),
        from: root));
  }

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
  stdout.writeln('  Files changed:');
  for (final t in touched) {
    stdout.writeln('    $t');
  }
  stdout.writeln('\n  Restore them before you commit:');
  stdout.writeln('    git checkout -- ${touched.join(' ')}\n');
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
  if (dryRun) {
    drift.add(rel);
  } else {
    file.writeAsStringSync(updated);
    stdout.writeln('    wrote $rel');
  }
}

void _printHelp() {
  stdout.writeln('''
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
  --app <id>        Only this app.
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
