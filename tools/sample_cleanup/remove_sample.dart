import 'dart:io';

import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';
import 'package:yaml/yaml.dart';

import '../shared/app_locator.dart';

/// Removes a sample bundle — the feature package *and* everything that travels
/// with it (domain/data pairs, workspace entries, DI registrations).
///
/// The template ships working reference features. Deleting one by hand is where
/// people get hurt: `auth` is not just `modules/auth/feature`, it is also
/// `domain_auth`, `data_auth`, and an entry in every app manifest that composes
/// them — plus what `composer sync` regenerates from those manifests. Miss one
/// and the workspace stops resolving.
///
/// Usage:
///   dart tools/sample_cleanup/remove_sample.dart --list
///   dart tools/sample_cleanup/remove_sample.dart auth           # preview
///   dart tools/sample_cleanup/remove_sample.dart auth --apply   # do it
///
/// It never edits [_manifestPath]. After `--apply` the bundle's definition is
/// still there while its packages are not, and that is how
/// `tools/docs_check/check.dart` recognises a documentation reference into a
/// removed sample: it reports those as expected fallout (INFO) instead of
/// failing CI Gate 5.
const String _manifestPath = 'tools/sample_manifest.yaml';

/// Shared files every removal rewrites in place.
///
/// Snapshotted before the first mutation so a failure partway through restores
/// them rather than leaving a workspace that references a deleted package.
/// Same contract as `CommonHelpers.sharedMutatedFiles` in the module generator.
/// `app_manifest.yaml` is the one that matters now: the other three are
/// generated between `composer:managed` markers, so removing lines from them
/// only holds until the next `composer sync`. They stay in the list so the tree
/// is consistent the moment this tool finishes, rather than referencing a
/// package that no longer exists until someone runs the generator.
///
/// Computed from every app in the workspace rather than naming
/// `apps/mobile/`: a sample removed from one app's manifest but left in
/// another's is exactly the half-deleted state this tool exists to prevent.
List<String> get _sharedMutatedFiles => [
  'pubspec.yaml',
  for (final app in discoverApps()) ...[
    '${app.dir}/app_manifest.yaml',
    '${app.dir}/pubspec.yaml',
    '${app.dir}/lib/di/injection.dart',
  ],
];

final Map<String, String?> _snapshots = {};

/// `--verbose`: list every doc reference instead of the first few.
var _verbose = false;
final List<String> _deletedDirs = [];

Future<void> main(List<String> args) async {
  if (!File(_manifestPath).existsSync()) {
    stderr.writeln(
      '[ERROR] $_manifestPath not found. '
      'Run this from the repository root.',
    );
    exitCode = 1;
    return;
  }

  final manifest = loadYaml(File(_manifestPath).readAsStringSync()) as YamlMap;

  if (args.isEmpty || args.contains('--help') || args.contains('-h')) {
    _printUsage();
    return;
  }

  // A misspelt flag must not be ignored: `home --aply` would silently be a
  // dry run, and `home --apply --bogus` used to apply.
  const knownFlags = {'--list', '--apply', '--verbose'};
  final unknown = args
      .where((a) => a.startsWith('-') && !knownFlags.contains(a))
      .toList();
  if (unknown.isNotEmpty) {
    stderr.writeln('[ERROR] Unknown flag(s): ${unknown.join(', ')}');
    stderr.writeln('');
    _printUsage(stderr);
    exitCode = 64;
    return;
  }

  if (args.contains('--list')) {
    _printClassification(manifest);
    return;
  }

  final positional = args.where((a) => !a.startsWith('-')).toList();
  if (positional.isEmpty) {
    stderr.writeln(
      '[ERROR] Missing bundle name. "--list" shows the choices.',
    );
    exitCode = 64;
    return;
  }
  if (positional.length > 1) {
    stderr.writeln(
      '[ERROR] One bundle per run — got: ${positional.join(', ')}',
    );
    exitCode = 64;
    return;
  }

  final bundleName = positional.first;
  final bundles = manifest['bundles'] as YamlMap;
  if (!bundles.containsKey(bundleName)) {
    stderr.writeln(
      '[ERROR] No bundle "$bundleName". '
      'Valid bundles: ${bundles.keys.join(', ')}',
    );
    exitCode = 64;
    return;
  }

  // Dry-run is the default on purpose: this deletes whole package directories,
  // and the repo may well have uncommitted work, so an accidental run must not
  // be destructive. Writing requires opting in with --apply.
  final apply = args.contains('--apply');
  _verbose = args.contains('--verbose');
  await _removeBundle(
    manifest: manifest,
    bundleName: bundleName,
    bundle: bundles[bundleName] as YamlMap,
    apply: apply,
  );
}

void _printUsage([IOSink? sink]) {
  (sink ?? stdout).writeln('''
Remove one sample bundle from the template.

  dart tools/sample_cleanup/remove_sample.dart --list
      Print the sample / framework / shell classification and the bundles.

  dart tools/sample_cleanup/remove_sample.dart <bundle>
      Preview (dry run) — writes NOTHING. This is the default.

  dart tools/sample_cleanup/remove_sample.dart <bundle> --apply
      Remove it for real, rolling the shared files back if a step fails.

  --verbose: list every documentation reference instead of the first few.

Both modes count the documentation (*.md) references to paths the removal
deletes. `dart tools/docs_check/check.dart` (CI Gate 5) reports them as an
INFO summary per removed bundle and does not fail on them — update the docs
at your leisure. This tool never edits $_manifestPath: docs_check reads the
bundle definitions there to recognise a removed sample.

Classification source: $_manifestPath
''');
}

void _printClassification(YamlMap manifest) {
  final packages = manifest['packages'] as YamlMap;

  final byKind = <String, List<MapEntry<String, YamlMap>>>{
    'framework': [],
    'shell': [],
    'sample': [],
  };
  packages.forEach((name, value) {
    final entry = value as YamlMap;
    final kind = entry['kind'] as String;
    byKind.putIfAbsent(kind, () => []).add(MapEntry(name as String, entry));
  });

  stdout.writeln('');
  stdout.writeln('PACKAGE CLASSIFICATION  (source: $_manifestPath)');
  stdout.writeln('=' * 78);

  const labels = {
    'framework': 'FRAMEWORK — keep. Deleting it breaks the template.',
    'shell':
        'SHELL — keep, but edit its manifest when you add or remove a feature.',
    'sample': 'SAMPLE — delete freely once you understand it.',
  };

  for (final kind in const ['framework', 'shell', 'sample']) {
    final entries = byKind[kind] ?? [];
    if (entries.isEmpty) continue;
    stdout.writeln('');
    stdout.writeln(labels[kind] ?? kind);
    stdout.writeln('-' * 78);
    for (final e in entries) {
      stdout.writeln('  ${e.key.padRight(28)} ${e.value['path']}');
    }
  }

  final bundles = manifest['bundles'] as YamlMap;
  stdout.writeln('');
  stdout.writeln('REMOVABLE BUNDLES: ${bundles.keys.join(', ')}');
  stdout.writeln(
    '  Preview: dart tools/sample_cleanup/remove_sample.dart <bundle>',
  );
  stdout.writeln('');
}

Future<void> _removeBundle({
  required YamlMap manifest,
  required String bundleName,
  required YamlMap bundle,
  required bool apply,
}) async {
  final packages = manifest['packages'] as YamlMap;
  final pkgNames = (bundle['packages'] as YamlList).cast<String>();

  final mode = apply ? 'APPLYING' : 'PREVIEW (dry run — nothing is written)';
  stdout.writeln('');
  stdout.writeln('Remove bundle "$bundleName"  —  $mode');
  stdout.writeln('=' * 78);

  // --- 1. Directories ------------------------------------------------------
  stdout.writeln('');
  stdout.writeln('Package directories to delete:');
  final dirs = <String>[];
  for (final name in pkgNames) {
    final entry = packages[name] as YamlMap?;
    if (entry == null) {
      stderr.writeln('  [WARN] "$name" is not in the manifest — skipped.');
      continue;
    }
    final path = entry['path'] as String;
    final exists = Directory(path).existsSync();
    stdout.writeln(
      '  ${exists ? '-' : 'x'} $path'
      '${exists ? '' : '   (absent — skipped)'}',
    );
    if (exists) dirs.add(path);
  }

  // --- 2. Shared file edits ------------------------------------------------
  stdout.writeln('');
  stdout.writeln('Shared files to edit:');
  final edits = _planSharedEdits(pkgNames, packages, bundleName: bundleName);
  if (edits.isEmpty) {
    stdout.writeln('  (no matching lines)');
  }
  for (final edit in edits) {
    stdout.writeln('  ${edit.file}');
    for (final line in edit.removedLines) {
      stdout.writeln('      - ${line.trim()}');
    }
  }

  // --- 3. Consequences the docs never covered ------------------------------
  final breaks = bundle['breaks'] as YamlList?;
  if (breaks != null && breaks.isNotEmpty) {
    stdout.writeln('');
    stdout.writeln('!! OTHER SAMPLES WILL BREAK — fix these by hand:');
    for (final b in breaks) {
      final m = b as YamlMap;
      stdout.writeln('  * ${m['sample']}  (${m['at']})');
      stdout.writeln('      why : ${m['why']}');
      stdout.writeln('      fix : ${m['fix']}');
    }
  }

  final orphans = bundle['orphaned_contracts'] as YamlList?;
  if (orphans != null && orphans.isNotEmpty) {
    stdout.writeln('');
    stdout.writeln(
      'core_di contracts that become dead code (delete them if you like):',
    );
    for (final o in orphans) {
      stdout.writeln('  ? $o');
    }
  }

  final keys = bundle['orphaned_keys'] as YamlList?;
  if (keys != null && keys.isNotEmpty) {
    for (final k in keys) {
      stdout.writeln('  ? $k');
    }
  }

  final safe = bundle['safe_couplings'] as YamlList?;
  if (safe != null && safe.isNotEmpty) {
    stdout.writeln('');
    stdout.writeln(
      'Safe couplings (getItOrNull + fallback, degrade on their own):',
    );
    for (final s in safe) {
      stdout.writeln('  ok $s');
    }
  }

  final note = bundle['note'] as String?;
  if (note != null) {
    stdout.writeln('');
    stdout.writeln('Note: $note');
  }

  // --- 3b. Documentation that will point at deleted paths ------------------
  final removedPaths = _removedPaths(dirs);
  final docRefs = _findDocReferences(removedPaths);
  _reportDocReferences(docRefs, applied: false);

  // --- 4. Execute ----------------------------------------------------------
  if (!apply) {
    stdout.writeln('');
    stdout.writeln('Nothing was changed. Add --apply to remove it for real.');
    stdout.writeln('');
    return;
  }

  stdout.writeln('');
  stdout.writeln('Applying...');
  _snapshotSharedFiles();
  try {
    for (final edit in edits) {
      File(edit.file).writeAsStringSync(edit.newContent);
      stdout.writeln('  edited  ${edit.file}');
    }
    for (final dir in dirs) {
      Directory(dir).deleteSync(recursive: true);
      _deletedDirs.add(dir);
      stdout.writeln('  deleted $dir');
    }
    // modules/<id>/ is left empty once its last layer is gone.
    for (final dir in dirs) {
      final parent = Directory(dir).parent;
      if (parent.existsSync() && parent.listSync().isEmpty) {
        parent.deleteSync();
        stdout.writeln('  deleted ${parent.path}');
      }
    }
  } catch (e) {
    stderr.writeln('[ERROR] Failed partway through: $e');
    stderr.writeln('[INFO] Restoring the shared files...');
    _rollback();
    stderr.writeln(
      '[INFO] Shared files restored. Deleted directories CANNOT be '
      'restored by this tool — recover them with git.',
    );
    exitCode = 1;
    return;
  }

  stdout.writeln('');
  stdout.writeln('Done. Next steps:');
  stdout.writeln('  dart tools/composer/composer.dart sync');
  stdout.writeln('  flutter pub get');
  stdout.writeln('  dart run build_runner build --workspace');
  stdout.writeln('  flutter analyze');
  stdout.writeln('  dart tools/arch_check/check.dart');
  if (docRefs.isNotEmpty) {
    stdout.writeln(
      '  # passes; summarises the ${docRefs.length} doc reference(s) to '
      '"$bundleName" as INFO',
    );
  }
  stdout.writeln('  dart tools/docs_check/check.dart');
  _reportDocReferences(docRefs, applied: true);
  stdout.writeln('');
}

/// A Markdown reference to a path the removal deletes.
class _DocRef {
  _DocRef(this.file, this.line, this.reference);

  final String file;
  final int line;
  final String reference;
}

/// The package directories, plus each parent (`modules/<id>`) left empty
/// once they are gone.
List<String> _removedPaths(List<String> dirs) {
  final removed = {...dirs};
  for (final dir in dirs) {
    final parent = Directory(dir).parent;
    if (!parent.existsSync()) continue;
    final remaining = parent.listSync().where((e) {
      final path = e.path.replaceAll('\\', '/');
      return !removed.contains(path) &&
          !removed.contains(path.replaceFirst('./', ''));
    });
    if (remaining.isEmpty) removed.add(parent.path.replaceAll('\\', '/'));
  }
  return removed.toList()..sort();
}

/// Directories `tools/docs_check/check.dart` never walks — kept identical so
/// the count here is the count that gate will report.
const _skippedDocDirs = {
  '.git',
  '.dart_tool',
  '.fvm',
  '.idea',
  '.symlinks',
  'build',
  'ephemeral',
  'node_modules',
  'Pods',
};

final _backtickSpan = RegExp(r'`([^`\n]+)`');
final _markdownLink = RegExp(r'\[[^\]\n]*\]\(([^)\s]+)(?:\s+"[^"]*")?\)');
final _codeFence = RegExp(r'^\s*```');

/// Every backticked path and relative Markdown link, outside code fences,
/// that names one of [removedPaths] or something inside it — what
/// `docs_check` (CI Gate 5) will call a dead reference after the removal.
///
/// Documents inside the removed directories are skipped: they go with them.
List<_DocRef> _findDocReferences(List<String> removedPaths) {
  if (removedPaths.isEmpty) return [];
  bool hits(String ref) =>
      removedPaths.any((r) => ref == r || ref.startsWith('$r/'));

  // Paths docs_check accepts as correctly absent (generated, gitignored).
  final allowlistFile = File('tools/docs_check/allowlist.txt');
  final allowlist = allowlistFile.existsSync()
      ? allowlistFile
            .readAsLinesSync()
            .map((l) => l.split('#').first.trim())
            .where((l) => l.isNotEmpty)
            .toSet()
      : <String>{};

  final docs = <File>[];
  void walk(Directory dir) {
    for (final entity in dir.listSync(followLinks: false)) {
      final path = entity.path.replaceAll('\\', '/').replaceFirst('./', '');
      final name = path.split('/').last;
      if (entity is Directory) {
        if (_skippedDocDirs.contains(name) || hits(path)) continue;
        walk(entity);
      } else if (entity is File && name.endsWith('.md')) {
        docs.add(entity);
      }
    }
  }

  walk(Directory('.'));
  docs.sort((a, b) => a.path.compareTo(b.path));

  // Whether every path fitting [pattern] is one the removal deletes — the
  // same test as docs_check's `_matchesSomething`, run against the tree as
  // it will be. Only patterns under a top-level directory a bundle lives in
  // can be affected. Like docs_check, a `<placeholder>` span is a template:
  // only its part before the first placeholder segment is checked.
  final patternCache = <String, bool>{};
  bool patternDies(String pattern) => patternCache.putIfAbsent(pattern, () {
    if (!const ['modules/', 'platform/', 'apps/'].any(pattern.startsWith)) {
      return false;
    }
    final segments = pattern.split('/');
    final cut = segments.indexWhere((s) => s.contains('<'));
    final globbable = cut < 0 ? pattern : segments.take(cut).join('/');
    if (!globbable.contains('*') && !globbable.contains('{')) {
      return hits(globbable);
    }
    try {
      final matches = Glob(globbable)
          .listSync(root: '.')
          .map((e) => e.path.replaceAll('\\', '/').replaceFirst('./', ''))
          .toList();
      return matches.isNotEmpty && matches.every(hits);
    } on FileSystemException {
      return false;
    } on FormatException {
      return false;
    }
  });

  final out = <_DocRef>[];
  for (final doc in docs) {
    final rel = doc.path.replaceAll('\\', '/').replaceFirst('./', '');
    final docDir = rel.contains('/')
        ? rel.substring(0, rel.lastIndexOf('/'))
        : '';
    final lines = doc.readAsLinesSync();
    var inFence = false;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (_codeFence.hasMatch(line)) {
        inFence = !inFence;
        continue;
      }
      if (inFence) continue;

      for (final m in _backtickSpan.allMatches(line)) {
        var ref = m.group(1)!.trim();
        // A shell line, not a path: docs_check skips it too.
        if (ref.isEmpty || ref.contains(' ')) continue;
        while (ref.endsWith('/')) {
          ref = ref.substring(0, ref.length - 1);
        }
        if (ref.isEmpty) continue;
        if (allowlist.contains(ref)) continue;
        if (ref.contains(RegExp(r'[*{<]'))) {
          // A set of paths (`modules/<name>/data/...`): docs_check needs at
          // least one real path to fit it, so it dies when every fit does.
          if (patternDies(ref)) out.add(_DocRef(rel, i + 1, ref));
          continue;
        }
        if (hits(ref)) out.add(_DocRef(rel, i + 1, ref));
      }
      for (final m in _markdownLink.allMatches(line)) {
        final target = m.group(1)!;
        if (target.startsWith('http://') ||
            target.startsWith('https://') ||
            target.startsWith('mailto:') ||
            target.startsWith('#')) {
          continue;
        }
        final path = target.split('#').first;
        if (path.isEmpty) continue;
        final resolved = _normalize(docDir.isEmpty ? path : '$docDir/$path');
        if (!allowlist.contains(resolved) && hits(resolved))
          out.add(_DocRef(rel, i + 1, '$target -> $resolved'));
      }
    }
  }
  return out;
}

/// `a/b/../c/./d` -> `a/c/d`.
String _normalize(String path) {
  final parts = <String>[];
  for (final part in path.split('/')) {
    if (part.isEmpty || part == '.') continue;
    if (part == '..') {
      if (parts.isNotEmpty) parts.removeLast();
      continue;
    }
    parts.add(part);
  }
  return parts.join('/');
}

void _reportDocReferences(List<_DocRef> refs, {required bool applied}) {
  if (refs.isEmpty) {
    if (!applied) {
      stdout.writeln('');
      stdout.writeln(
        'Docs: no references to the paths being removed.',
      );
    }
    return;
  }
  final files = refs.map((r) => r.file).toSet();
  // Informational, not an error: docs_check passes on these (see its
  // removed-sample summary).
  final sink = stdout;
  sink.writeln('');
  sink.writeln(
    'Docs: ${refs.length} reference(s) in ${files.length} .md file(s) '
    '${applied ? 'now point' : 'will point'} to removed paths.',
  );
  sink.writeln(
    '   Expected: `dart tools/docs_check/check.dart` (CI Gate 5) reports them '
    'as INFO for this removed bundle and still passes. Update them at your '
    'leisure.',
  );
  final shown = _verbose ? refs.length : 15;
  for (final ref in refs.take(shown)) {
    sink.writeln('   ${ref.file}:${ref.line}  ${ref.reference}');
  }
  if (refs.length > shown) {
    sink.writeln(
      '   … and ${refs.length - shown} more'
      ' — add --verbose (or run `dart tools/docs_check/check.dart --verbose` after removing) to see them all.',
    );
  }
}

class _FileEdit {
  _FileEdit(this.file, this.removedLines, this.newContent);

  final String file;
  final List<String> removedLines;
  final String newContent;
}

/// Works out which lines each shared file loses, without writing anything.
///
/// Line-oriented rather than YAML/AST-aware on purpose: these files carry
/// comments and grouping that a re-serialise would flatten, and the module
/// generator already edits them the same way.
List<_FileEdit> _planSharedEdits(
  List<String> pkgNames,
  YamlMap packages, {
  required String bundleName,
}) {
  final edits = <_FileEdit>[];

  final paths = <String, String>{};
  for (final name in pkgNames) {
    final entry = packages[name] as YamlMap?;
    if (entry != null) paths[name] = entry['path'] as String;
  }

  for (final file in _sharedMutatedFiles) {
    final f = File(file);
    if (!f.existsSync()) continue;

    final lines = f.readAsLinesSync();
    final keep = <String>[];
    final removed = <String>[];

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      var drop = false;

      for (final name in pkgNames) {
        // injection.dart: `import 'package:feature_auth/di/module.module.dart';`
        if (line.contains('package:$name/di/module.module.dart')) drop = true;

        // injection.dart: `  ExternalModule(FeatureAuthPackageModule),`
        if (line.contains('ExternalModule(${_moduleClass(name)})')) drop = true;

        // root pubspec: `  - modules/auth/feature`
        final path = paths[name];
        if (path != null && RegExp('^\\s*-\\s+$path\\s*\$').hasMatch(line)) {
          drop = true;
        }

        // app_manifest.yaml: `      - core_foo` in a di_group or
        // `extra_dependencies`.
        if (RegExp('^\\s+-\\s+$name\\s*\$').hasMatch(line)) drop = true;

        // an app's pubspec.yaml: `  feature_auth:` followed by `    path: ...`
        if (RegExp('^\\s{2}$name:\\s*\$').hasMatch(line)) {
          drop = true;
          if (i + 1 < lines.length && lines[i + 1].trim().startsWith('path:')) {
            removed.add(lines[i + 1]);
            i++; // consume the path line with it
          }
        }
      }

      // app_manifest.yaml: `  - { id: auth, layers: [domain, data, feature] }`
      if (RegExp('^\\s*-\\s*\\{\\s*id:\\s*$bundleName\\s*,').hasMatch(line)) {
        drop = true;
      }

      if (drop) {
        removed.add(line);
      } else {
        keep.add(line);
      }
    }

    if (removed.isNotEmpty) {
      edits.add(_FileEdit(file, removed, '${keep.join('\n')}\n'));
    }
  }

  return edits;
}

/// `feature_auth` -> `FeatureAuthPackageModule`.
String _moduleClass(String packageName) {
  final pascal = packageName
      .split('_')
      .where((p) => p.isNotEmpty)
      .map((p) => p[0].toUpperCase() + p.substring(1))
      .join();
  return '${pascal}PackageModule';
}

void _snapshotSharedFiles() {
  _snapshots.clear();
  for (final path in _sharedMutatedFiles) {
    final file = File(path);
    _snapshots[path] = file.existsSync() ? file.readAsStringSync() : null;
  }
}

/// Best-effort restore: reports what it could not undo rather than throwing,
/// because it runs while another error is already propagating.
void _rollback() {
  _snapshots.forEach((path, original) {
    try {
      final file = File(path);
      if (original == null) {
        if (file.existsSync()) file.deleteSync();
      } else {
        file.writeAsStringSync(original);
      }
    } catch (e) {
      stderr.writeln('  [WARN] could not restore $path ($e)');
    }
  });
}
