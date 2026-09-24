import 'dart:io';

import '../unused_checker/output_formatter.dart';

/// Makes a partial checkout resolvable, so `composer.dart` can run at all.
///
/// `composer.dart` imports `package:path` and `package:yaml`, so it needs a
/// resolved workspace — and a partial checkout does not resolve. The root
/// `pubspec.yaml` still lists every module in its `workspace:` list and each
/// app's pubspec still has a path dependency on it; a module whose submodule
/// was never initialised is an empty directory with no `pubspec.yaml`, and
/// `flutter pub get` refuses the whole workspace over it. Composer needs pub,
/// and pub needs what composer would write.
///
/// This breaks the cycle. It imports **no package** — only `dart:io` and a
/// sibling file that does the same — so it runs on a fresh clone with no
/// `.dart_tool/`. It prunes, from the composer-managed regions only:
///
///  * the root `workspace:` list — every entry whose directory has no
///    `pubspec.yaml`;
///  * each app's `composer:managed:deps` region — every path dependency on
///    such a directory.
///
/// It resolves nothing and composes nothing. Once `flutter pub get` succeeds,
/// `dart tools/composer/composer.dart sync` rewrites the same regions — and
/// every app's `injection.dart` — properly from the manifests.
///
/// ```
/// dart tools/composer/bootstrap.dart [--dry-run]
/// ```

const _usage = '''
Composer bootstrap — make a partial checkout resolvable for `composer.dart`.

USAGE
  dart tools/composer/bootstrap.dart [--dry-run]

Run from the repository root, in a checkout where some module submodules are
not initialised (their directory is empty). Removes, from the composer-managed
regions only, every workspace member and every app path dependency whose
directory has no pubspec.yaml. Uses no package, so it runs before
`flutter pub get` can.

Then:
  flutter pub get
  dart tools/composer/composer.dart sync
  dart tools/workspace_setup/configure.dart

OPTIONS
  --dry-run   Report what would be pruned; write nothing.
  --help      Show this help.

EXIT CODES
  0   pruned, or nothing to prune
  1   not a composer workspace, or a present package still depends on a
      missing one (nothing written)
  64  bad usage''';

void main(List<String> args) {
  var dryRun = false;
  for (final arg in args) {
    switch (arg) {
      case '--help' || '-h':
        stdout.writeln(_usage);
        exit(0);
      case '--dry-run':
        dryRun = true;
      default:
        OutputFormatter.printError('Unknown argument `$arg`.');
        stderr.writeln(_usage);
        exit(64);
    }
  }

  final rootPubspec = File('pubspec.yaml');
  if (!rootPubspec.existsSync() ||
      !rootPubspec.readAsStringSync().contains('composer:managed:workspace')) {
    OutputFormatter.printError(
      'No `composer:managed:workspace` region in ./pubspec.yaml. Run this '
      'from the repository root.',
    );
    exit(1);
  }

  OutputFormatter.printHeader(
    'Composer — bootstrap',
    subtitle: dryRun ? 'dry run' : 'prune what is not on disk',
  );

  // -- root workspace list ----------------------------------------------------
  final rootLines = rootPubspec.readAsLinesSync();
  final workspace = _region(rootLines, 'workspace');
  if (workspace == null) {
    OutputFormatter.printError(
      'pubspec.yaml: the `composer:managed:workspace` / '
      '`composer:end:workspace` marker pair is broken. Restore it with '
      '`git checkout -- pubspec.yaml`.',
    );
    exit(1);
  }

  final entry = RegExp(r'^\s*-\s*(\S+)\s*$');
  final members = <String>[];
  final prunedMembers = <String>[];
  final keptRoot = <String>[];
  for (var i = 0; i < rootLines.length; i++) {
    final line = rootLines[i];
    final m = i > workspace.begin && i < workspace.end
        ? entry.firstMatch(line)
        : null;
    if (m != null) {
      final dir = _trimSlash(m.group(1)!);
      if (!_hasPubspec(dir)) {
        prunedMembers.add(dir);
        continue;
      }
      members.add(dir);
    }
    keptRoot.add(line);
  }

  // -- each app's managed path dependencies -----------------------------------
  final edits = <String, List<String>>{}; // pubspec path -> new lines
  final prunedDeps = <String, List<String>>{}; // pubspec path -> packages
  for (final member in members) {
    final path = '$member/pubspec.yaml';
    final lines = File(path).readAsLinesSync();
    final deps = _region(lines, 'deps');
    if (deps == null) continue; // not an app, or no managed region

    final kept = <String>[];
    final dropped = <String>[];
    final header = RegExp(r'^  ([A-Za-z_]\w*):\s*$');
    var i = 0;
    while (i < lines.length) {
      final h = i > deps.begin && i < deps.end
          ? header.firstMatch(lines[i])
          : null;
      if (h == null) {
        kept.add(lines[i++]);
        continue;
      }
      // One entry: the `  name:` line plus every deeper-indented line under it.
      final block = [lines[i++]];
      while (i < deps.end && lines[i].startsWith('    ')) {
        block.add(lines[i++]);
      }
      final target = _pathOf(block);
      if (target != null && !_hasPubspec(_join(member, target))) {
        dropped.add(h.group(1)!);
      } else {
        kept.addAll(block);
      }
    }
    if (dropped.isNotEmpty) {
      edits[path] = kept;
      prunedDeps[path] = dropped;
    }
  }

  // -- what pruning cannot fix --------------------------------------------------
  // A hand-written path dependency (outside any managed region) on a missing
  // directory — a present module needing another team's module. Pruning the
  // workspace list cannot help: pub still fails, only on a different line.
  final blockers = <String>[];
  for (final member in members) {
    final path = '$member/pubspec.yaml';
    final lines = File(path).readAsLinesSync();
    final managed = _region(lines, 'deps');
    for (var i = 0; i < lines.length; i++) {
      if (managed != null && i > managed.begin && i < managed.end) continue;
      final m = _pathLine.firstMatch(lines[i]);
      if (m == null || !_isSourceKey(lines, i)) continue;
      final target = _join(member, m.group(1)!);
      if (!_hasPubspec(target)) {
        blockers.add(
          '$path:${i + 1} depends on `$target`, which is not on disk',
        );
      }
    }
  }
  if (blockers.isNotEmpty) {
    for (final b in blockers) {
      OutputFormatter.printError('  $b');
    }
    OutputFormatter.printError(
      'Nothing was written: a module that is present depends on one that is '
      'not, and no managed region can drop that. Initialise the missing '
      'submodule too (`git submodule update --init <path>`).',
    );
    exit(1);
  }

  if (prunedMembers.isEmpty && prunedDeps.isEmpty) {
    OutputFormatter.printSuccess(
      'Every workspace member is on disk — nothing to prune. Run '
      '`flutter pub get`.',
    );
    exit(0);
  }

  // -- report, then write ---------------------------------------------------------
  final verb = dryRun ? 'would prune' : 'pruned';
  stdout.writeln(
    '  pubspec.yaml — $verb ${prunedMembers.length} workspace '
    'member(s) with no pubspec.yaml:',
  );
  for (final d in prunedMembers) {
    stdout.writeln('    - $d');
  }
  for (final e in prunedDeps.entries) {
    stdout.writeln(
      '  ${e.key} — $verb ${e.value.length} path dependency(ies):',
    );
    for (final d in e.value) {
      stdout.writeln('    - $d');
    }
  }

  if (dryRun) {
    stdout.writeln('\n  Dry run: nothing was written.');
    exit(0);
  }

  final written = <String>[];
  if (prunedMembers.isNotEmpty) {
    _writeLines(rootPubspec, keptRoot);
    written.add('pubspec.yaml');
  }
  for (final e in edits.entries) {
    _writeLines(File(e.key), e.value);
    written.add(e.key);
  }

  stdout.writeln('');
  OutputFormatter.printWarning(
    'These files are committed. What was written is only a stepping stone — '
    'never commit it.',
  );
  stdout.writeln('  Next, from the repository root:');
  stdout.writeln('    flutter pub get');
  stdout.writeln('    dart tools/composer/composer.dart sync');
  stdout.writeln('    dart tools/workspace_setup/configure.dart');
  stdout.writeln(
    '\n  `sync` names only the files *it* changes, so it will not repeat '
    'these.\n  Restore them — with whatever `sync` names — before you commit:',
  );
  stdout.writeln('    git checkout -- ${written.join(' ')}');
}

/// Line indexes of the `composer:managed:<name>` and `composer:end:<name>`
/// markers, or null when either is missing or they are out of order.
({int begin, int end})? _region(List<String> lines, String name) {
  final begin = lines.indexWhere((l) => l.contains('composer:managed:$name'));
  final end = lines.indexWhere((l) => l.contains('composer:end:$name'));
  if (begin == -1 || end == -1 || end < begin) return null;
  return (begin: begin, end: end);
}

/// A `path:` line of a dependency entry; group 1 is the path, unquoted.
final _pathLine = RegExp(r'''^\s+path:\s*["']?([^"'#\s]+)''');

/// Whether the `path:` key on line [i] is a dependency's *source* — nested
/// under a package name — rather than a package named `path` sitting directly
/// under `dependencies:`.
bool _isSourceKey(List<String> lines, int i) {
  int indent(String l) => l.length - l.trimLeft().length;
  final own = indent(lines[i]);
  for (var j = i - 1; j >= 0; j--) {
    final t = lines[j].trim();
    if (t.isEmpty || t.startsWith('#')) continue;
    if (indent(lines[j]) < own) return indent(lines[j]) > 0;
  }
  return false;
}

/// The `path:` value of one dependency entry, or null for a non-path entry.
String? _pathOf(List<String> block) {
  for (final line in block.skip(1)) {
    final m = _pathLine.firstMatch(line);
    if (m != null) return m.group(1);
  }
  return null;
}

bool _hasPubspec(String dir) => File('$dir/pubspec.yaml').existsSync();

String _trimSlash(String dir) =>
    dir.replaceAll(r'\', '/').replaceFirst(RegExp(r'/+$'), '');

/// [relative] resolved against [from], both repo-relative, `..` collapsed.
String _join(String from, String relative) {
  final parts = <String>[];
  for (final seg in '${_trimSlash(from)}/${_trimSlash(relative)}'.split('/')) {
    if (seg.isEmpty || seg == '.') continue;
    if (seg == '..' && parts.isNotEmpty && parts.last != '..') {
      parts.removeLast();
    } else {
      parts.add(seg);
    }
  }
  return parts.join('/');
}

/// Writes [lines] back with the file's own trailing newline convention.
void _writeLines(File file, List<String> lines) {
  final original = file.readAsStringSync();
  final eol = original.contains('\r\n') ? '\r\n' : '\n';
  final trailing = original.endsWith('\n') ? eol : '';
  file.writeAsStringSync(lines.join(eol) + trailing);
}
