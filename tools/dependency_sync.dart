import 'dart:io';

import 'package:yaml/yaml.dart';

import 'shared/toolchain.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.contains('--help') || arguments.contains('-h')) {
    stdout.writeln('''
Dependency Sync — aligns every workspace pubspec with pubspec_dependencies.yaml.

USAGE
  dart tools/dependency_sync.dart           rewrite drifted versions, then pub get
  dart tools/dependency_sync.dart --check   report drift only; exit 1 on any (CI Gate 4)
''');
    exit(0);
  }
  // An unknown flag used to fall through to a real sync — `--help` included,
  // which rewrote pubspecs and ran `pub get` for someone asking for usage.
  final unknown = arguments.where((a) => a != '--check').toList();
  if (unknown.isNotEmpty) {
    stderr.writeln('❌ Unknown argument(s): ${unknown.join(' ')}. See --help.');
    exit(64);
  }
  final bool isCheckMode = arguments.contains('--check');
  stdout.writeln(
    '================================================================',
  );
  stdout.writeln('📦 Dependency Sync & Catalog Manager for Monorepo Workspace');
  stdout.writeln(
    '================================================================',
  );

  final rootDir = Directory.current;
  final catalogFile = File('${rootDir.path}/pubspec_dependencies.yaml');

  if (!catalogFile.existsSync()) {
    stderr.writeln(
      '❌ Error: pubspec_dependencies.yaml not found at root directory!',
    );
    exit(1);
  }

  // 1. Parse Dependency Catalog — with a YAML parser, and refused outright
  // when it is not the shape this tool pins from. It used to be read line by
  // line: `dependencies: # note` did not match the header, so every runtime
  // pin was dropped and `--check` (CI Gate 4) passed on a catalog it had not
  // read; a `git:` block was written into pubspecs as `dio: ""`.
  final problems = <String>[];
  final catalog = _loadCatalog(catalogFile, problems);
  if (problems.isNotEmpty) {
    _refuse(problems, 'pubspec_dependencies.yaml');
  }

  stdout.writeln(
    '📌 Catalog loaded: ${catalog.length} shared dependencies registered.',
  );

  // 2. Discover pubspec.yaml files from root workspace settings
  final rootPubspec = File('${rootDir.path}/pubspec.yaml');
  if (!rootPubspec.existsSync()) {
    stderr.writeln('❌ Error: Root pubspec.yaml not found!');
    exit(1);
  }

  final rootDoc = _loadYaml(rootPubspec, 'pubspec.yaml', problems);
  final List<String> packagePaths = [];
  final workspace = rootDoc is YamlMap ? rootDoc['workspace'] : null;
  if (workspace is YamlList) {
    for (final entry in workspace) {
      if (entry is String) packagePaths.add(entry.trim());
    }
  }
  packagePaths.add('.');

  // Every pubspec is parsed before anything is compared or written: one that
  // does not parse is refused by name, and a sync never leaves half the
  // workspace rewritten around it.
  final pubspecs = <_Pubspec>[];
  for (final pkgPath in packagePaths) {
    final pubspecFile = File('${rootDir.path}/$pkgPath/pubspec.yaml');
    if (!pubspecFile.existsSync()) continue;
    final relativePath = pkgPath == '.'
        ? 'pubspec.yaml'
        : '$pkgPath/pubspec.yaml';
    final doc = pkgPath == '.'
        ? rootDoc
        : _loadYaml(pubspecFile, relativePath, problems);
    if (doc == null) continue; // reported
    if (doc is! YamlMap) {
      problems.add('$relativePath: expected a map, got ${_describe(doc)}');
      continue;
    }
    pubspecs.add(_Pubspec(pkgPath, pubspecFile, relativePath, doc));
  }
  if (problems.isNotEmpty) _refuse(problems, 'a workspace pubspec');

  final Map<String, String> workspacePackageDirs = {};
  for (final pubspec in pubspecs) {
    final name = pubspec.doc['name'];
    if (name is String) workspacePackageDirs[name] = pubspec.pkgPath;
  }

  stdout.writeln(
    '📂 Discovered ${packagePaths.length} workspace packages/directories.',
  );
  stdout.writeln(
    '🏷️  Workspace packages indexed: ${workspacePackageDirs.length}.',
  );

  int totalSynced = 0;
  int totalMismatches = 0;
  int totalRepairedPaths = 0;

  for (final pubspec in pubspecs) {
    final relativePath = pubspec.pkgPath == '.'
        ? 'Root (pubspec.yaml)'
        : pubspec.relativePath;
    final source = pubspec.file.readAsStringSync();
    final edits = <_Edit>[];

    // The YAML tree says *what* to change; the edit itself replaces only the
    // characters of that one value, so comments, quoting elsewhere, key
    // order and line endings stay exactly as they were.
    for (final section in const ['dependencies', 'dev_dependencies']) {
      final deps = pubspec.doc.nodes[section];
      if (deps is! YamlMap) continue;

      for (final entry in deps.nodes.entries) {
        final key = entry.key as YamlNode;
        final depName = key is YamlScalar ? key.value : null;
        if (depName is! String) continue;
        final value = entry.value;
        // An alias (`*anchor`) points at a node written elsewhere; editing
        // it would edit the anchor. Nothing in the workspace uses one.
        if (value.span.start.offset < key.span.end.offset) continue;

        // Workspace package: only its local `path:` is ours to repair.
        if (workspacePackageDirs.containsKey(depName)) {
          final pathNode = value is YamlMap ? value.nodes['path'] : null;
          if (pathNode is! YamlScalar) continue;
          final expectedPath = _relativePathBetween(
            pubspec.pkgPath,
            workspacePackageDirs[depName]!,
          );
          final cleanedPath = '${pathNode.value}';
          if (cleanedPath == expectedPath) continue;
          if (isCheckMode) {
            totalMismatches++;
            stderr.writeln(
              '⚠️  Broken local path: [$relativePath] $depName -> path: "$cleanedPath" (expected "$expectedPath")',
            );
          } else {
            stdout.writeln(
              '🔧 Repairing local path: [$relativePath] $depName -> path: "$expectedPath"',
            );
            edits.add(_Edit.replace(pathNode, expectedPath));
            totalRepairedPaths++;
          }
          continue;
        }

        final targetVersion = catalog[depName];
        // A map value is a `path:` / `git:` / `sdk:` / `hosted:` source —
        // not a version, and not the catalog's to overwrite.
        if (targetVersion == null || value is! YamlScalar) continue;

        if (value.value == null) {
          // Empty catalog dep (e.g. `dynamic_logger:`) — fill it in.
          totalMismatches++;
          if (isCheckMode) {
            stderr.writeln(
              '⚠️  Missing version: [$relativePath] $depName (expected "$targetVersion")',
            );
          } else {
            stdout.writeln(
              '⚡ Syncing missing: [$relativePath] -> $depName: "$targetVersion"',
            );
            edits.add(_Edit.fillEmpty(source, key, targetVersion));
          }
          continue;
        }

        final currentVersion = '${value.value}';
        if (currentVersion == targetVersion) continue;
        totalMismatches++;
        if (isCheckMode) {
          stderr.writeln(
            '⚠️  Mismatch: [$relativePath] uses $depName: "$currentVersion" instead of "$targetVersion"',
          );
        } else {
          stdout.writeln(
            '⚡ Syncing: [$relativePath] -> $depName from "$currentVersion" to "$targetVersion"',
          );
          edits.add(_Edit.replace(value, '"$targetVersion"'));
        }
      }
    }

    if (edits.isNotEmpty && !isCheckMode) {
      edits.sort((a, b) => b.start.compareTo(a.start));
      var updated = source;
      for (final edit in edits) {
        updated = updated.replaceRange(edit.start, edit.end, edit.text);
      }
      pubspec.file.writeAsStringSync(updated);
      totalSynced++;
    }
  }

  stdout.writeln(
    '================================================================',
  );
  if (isCheckMode) {
    if (totalMismatches > 0) {
      stderr.writeln(
        '❌ Mismatch detected! $totalMismatches dependency discrepancies found in the workspace.',
      );
      stderr.writeln(
        '💡 Run `dart tools/dependency_sync.dart` to automatically resolve all discrepancies.',
      );
      exit(1);
    } else {
      stdout.writeln(
        '✅ Success: All packages in the workspace are in perfect sync with the catalog!',
      );
    }
    // `--check` is read-only: no `pub get`, so it cannot touch the lockfile
    // or `.dart_tool/`.
    return;
  } else {
    if (totalSynced > 0) {
      stdout.writeln(
        '🚀 Successfully updated and synchronized $totalSynced packages with the dependency catalog.',
      );
      if (totalRepairedPaths > 0) {
        stdout.writeln(
          '🔧 Repaired $totalRepairedPaths broken local package paths.',
        );
      }
    } else {
      stdout.writeln(
        '✅ All packages in the workspace are already in perfect synchronization!',
      );
    }
  }

  // The repo's toolchain — `fvm dart` when FVM is configured and installed —
  // the same detection every tool that shells out uses.
  reportToolchain();
  stdout.writeln('💡 Running `dart pub get` to apply the updates...');
  final getResult = await Process.run(dartExecutable, [
    ...dartArgs,
    'pub',
    'get',
  ], runInShell: true);

  if (getResult.exitCode != 0) {
    stderr.writeln('❌ `dart pub get` failed after syncing:');
    stderr.writeln(getResult.stderr);
    exit(1);
  }

  stdout.writeln(
    '================================================================',
  );
}

/// Top-level sections the catalog may hold. Anything else is refused: a
/// typo such as `dev_dependancies:` would otherwise drop every pin under it.
const _catalogSections = ['dependencies', 'dev_dependencies'];

final _packageName = RegExp(r'^[a-z_][a-z0-9_]*$');

/// The catalog as package -> version constraint, both sections merged.
///
/// Adds one `pubspec_dependencies.yaml: <key>: <problem>` line to [problems]
/// per defect, and returns what it could read (the caller refuses on any).
Map<String, String> _loadCatalog(File file, List<String> problems) {
  const name = 'pubspec_dependencies.yaml';
  final catalog = <String, String>{};
  final owner = <String, String>{};
  final doc = _loadYaml(file, name, problems);
  if (problems.isNotEmpty) return catalog;
  if (doc is! YamlMap) {
    problems.add(
      '$name: (root): expected a map with `dependencies:` and '
      '`dev_dependencies:`, got '
      '${doc == null ? 'an empty file' : _describe(doc)}',
    );
    return catalog;
  }

  for (final key in doc.keys) {
    if (!_catalogSections.contains(key)) {
      problems.add(
        '$name: $key: unknown section — expected '
        '${_catalogSections.join(' or ')}',
      );
    }
  }

  for (final section in _catalogSections) {
    final deps = doc[section];
    if (deps == null) continue; // absent, or a header with nothing under it
    if (deps is! YamlMap) {
      problems.add(
        '$name: $section: expected a map of package: "version", got '
        '${_describe(deps)}',
      );
      continue;
    }
    for (final entry in deps.entries) {
      final pkg = entry.key;
      final version = entry.value;
      final where = '$name: $section.$pkg';
      if (pkg is! String || !_packageName.hasMatch(pkg)) {
        problems.add('$where: not a package name');
        continue;
      }
      if (version is! String || version.trim().isEmpty) {
        problems.add(
          '$where: expected a version constraint string (e.g. "^1.2.3"), got '
          '${_describe(version)}${switch (version) {
            num() => ' — quote it',
            YamlMap() => ' — the catalog pins versions only; a git/path/hosted source belongs in the package\'s own pubspec',
            _ => '',
          }}',
        );
        continue;
      }
      final previous = owner[pkg];
      if (previous != null) {
        problems.add('$where: already pinned under `$previous`');
        continue;
      }
      owner[pkg] = section;
      catalog[pkg] = version.trim();
    }
  }
  return catalog;
}

/// Parses [file]; on invalid YAML adds `<name>:<line>: not valid YAML — …`
/// to [problems] and returns null.
Object? _loadYaml(File file, String name, List<String> problems) {
  try {
    return loadYaml(file.readAsStringSync(), sourceUrl: file.uri);
  } on YamlException catch (e) {
    final line = e.span == null ? '' : ':${e.span!.start.line + 1}';
    problems.add(
      '$name$line: not valid YAML — '
      '${e.message.replaceFirst(RegExp(r'\.+$'), '')}',
    );
    return null;
  }
}

/// Prints [problems] and exits 1, before anything has been written.
Never _refuse(List<String> problems, String what) {
  for (final problem in problems) {
    stderr.writeln('❌ $problem');
  }
  stderr.writeln(
    '❌ Refusing to sync: fix $what first. Nothing was checked or written.',
  );
  exit(1);
}

/// `a string (`x`)`, `a map`, `nothing` — for "expected X, got Y".
String _describe(Object? value) => switch (value) {
  null => 'nothing',
  String() => 'a string (`$value`)',
  bool() => 'a boolean (`$value`)',
  num() => 'a number (`$value`)',
  List() => 'a list',
  Map() => 'a map',
  _ => 'a ${value.runtimeType}',
};

/// A workspace pubspec, parsed.
class _Pubspec {
  _Pubspec(this.pkgPath, this.file, this.relativePath, this.doc);

  final String pkgPath;
  final File file;
  final String relativePath;
  final YamlMap doc;
}

/// A replacement of `source[start, end)` with [text].
class _Edit {
  _Edit(this.start, this.end, this.text);

  /// Replaces exactly the characters of one scalar (quotes included).
  _Edit.replace(YamlNode node, String text)
    : this(node.span.start.offset, node.span.end.offset, text);

  /// Gives `name:` (no value) a version: the `:` and the blanks after it
  /// become `: "<version>"`, and a trailing `# comment` stays.
  factory _Edit.fillEmpty(String source, YamlNode key, String version) {
    final start = key.span.end.offset;
    final colon = RegExp(r'[ \t]*:[ \t]*').matchAsPrefix(source, start);
    final end = colon?.end ?? start;
    final commentFollows = end < source.length && source[end] == '#';
    return _Edit(start, end, ': "$version"${commentFollows ? ' ' : ''}');
  }

  final int start;
  final int end;
  final String text;
}

String _relativePathBetween(String fromDir, String toDir) {
  final fromParts = _normalizePath(fromDir).split('/');
  final toParts = _normalizePath(toDir).split('/');

  var commonPrefixLength = 0;
  while (commonPrefixLength < fromParts.length &&
      commonPrefixLength < toParts.length &&
      fromParts[commonPrefixLength] == toParts[commonPrefixLength]) {
    commonPrefixLength++;
  }

  final upLevels = List<String>.filled(
    fromParts.length - commonPrefixLength,
    '..',
  );
  final downLevels = toParts.sublist(commonPrefixLength);

  if (upLevels.isEmpty && downLevels.isEmpty) {
    return '.';
  }

  return [...upLevels, ...downLevels].join('/');
}

String _normalizePath(String path) {
  return path.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), '');
}
