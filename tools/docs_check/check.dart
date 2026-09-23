import 'dart:io';

import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';
import 'package:path/path.dart' as p;

/// Mechanical accuracy check for the Markdown documentation.
///
/// Prose rots silently: a package gets renamed, a file moves, and the guide
/// telling a newcomer to open it keeps saying the old name. `flutter analyze`
/// cannot see a sentence, so this is the only thing standing between the docs
/// and quiet decay.
///
/// Two classes of reference are verified:
///
///   1. **Backticked repo paths** — `` `platform/kernel/lib/...` `` — any
///      backtick span that starts with a real top-level directory of this
///      repo. A span that does not (`utils/`, `routing/`, `ViewState`) is a
///      convention or a symbol, not a path, and is ignored.
///   2. **Markdown links** — `[text](target)` — resolved relative to the file
///      that contains them, not to the current working directory. External
///      URLs and pure anchors are skipped.
///
/// Paths that are *correctly* absent live in `allowlist.txt` next to this
/// file, each with the reason it is not on disk. Generated output, gitignored
/// secrets, and "Step 1 — create this file" tutorial targets are the three
/// legitimate cases; everything else is drift.
///
/// Exit code 0 = clean, 1 = at least one dead reference.

/// Directories never walked for Markdown: tool state, build output, and the
/// native dependency trees Flutter and CocoaPods fetch.
///
/// Every other `.md` in the repository is checked. The scope used to be four
/// roots (`docs`, `.agents`, `README.md`, `CLAUDE.md`), which left
/// `README.vi.md`, `tools/README.md`, the `.github` guides and every package
/// README unchecked — 11 dead links had collected there when it was widened.
const _skippedDirs = <String>{
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

/// A backtick span is only treated as a path when it starts with one of
/// these. Everything else in backticks is a symbol, a command, or a
/// directory *convention* (`utils/`) that exists in many packages at once.
const _topLevelDirs = <String>[
  'app/',
  'apps/',
  // `packages/` and a bare `app/` are kept after the relayout on purpose:
  // nothing lives at either path any more, so a document still pointing
  // there is drift, and leaving the prefixes in this list is what makes the
  // gate say so instead of skipping them.
  'packages/',
  'tools/',
  'docs/',
  '.agents/',
  '.github/',
  'modules/',
  'platform/',
];

final _backtickSpan = RegExp(r'`([^`\n]+)`');
final _markdownLink = RegExp(r'\[[^\]\n]*\]\(([^)\s]+)(?:\s+"[^"]*")?\)');
final _codeFence = RegExp(r'^\s*```');

class _Hit {
  _Hit(this.docFile, this.line, this.reference, this.kind);

  final String docFile;
  final int line;
  final String reference;
  final String kind;
}

void main(List<String> args) {
  if (args.contains('--help') || args.contains('-h')) {
    stdout.writeln(_usage);
    return;
  }

  final repoRoot = _findRepoRoot();
  final verbose = args.contains('--verbose') || args.contains('-v');

  final allowlist = _readAllowlist(repoRoot);
  final docs = _collectDocs(repoRoot);

  if (docs.isEmpty) {
    stderr.writeln('docs_check: no Markdown files found under $repoRoot');
    exit(1);
  }

  final hits = <_Hit>[];
  var checked = 0;

  for (final doc in docs) {
    final relDoc = p.posix.relative(_posix(doc.path), from: _posix(repoRoot));
    final lines = doc.readAsLinesSync();
    var inFence = false;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (_codeFence.hasMatch(line)) {
        inFence = !inFence;
        continue;
      }

      // A fence is sample output — a path inside one is being shown, not
      // pointed at. Skip the whole block rather than half of it.
      if (inFence) continue;

      for (final m in _backtickSpan.allMatches(line)) {
        final raw = m.group(1)!.trim();
        final pattern = _asPattern(raw);
        if (pattern != null) {
          if (!_looksLikeRepoPath(pattern)) continue;
          checked++;
          if (allowlist.contains(pattern)) continue;
          if (_matchesSomething(repoRoot, pattern)) continue;
          hits.add(_Hit(relDoc, i + 1, pattern, 'pattern'));
          continue;
        }
        final ref = _normalisePath(raw);
        if (ref == null) continue;
        if (!_looksLikeRepoPath(ref)) continue;
        checked++;
        if (allowlist.contains(ref)) continue;
        if (_exists(repoRoot, ref)) continue;
        hits.add(_Hit(relDoc, i + 1, ref, 'path'));
      }

      for (final m in _markdownLink.allMatches(line)) {
        final target = m.group(1)!;
        if (_isExternal(target)) continue;
        final withoutAnchor = target.split('#').first;
        if (withoutAnchor.isEmpty) continue;
        final resolved = p.posix.normalize(
          p.posix.join(p.posix.dirname(relDoc), withoutAnchor),
        );
        checked++;
        if (allowlist.contains(resolved)) continue;
        if (_exists(repoRoot, resolved)) continue;
        hits.add(_Hit(relDoc, i + 1, '$target -> $resolved', 'link'));
      }
    }
  }

  stdout.writeln('Docs accuracy check');
  stdout.writeln('  documents : ${docs.length}');
  stdout.writeln('  references: $checked');
  stdout.writeln('  allowlist : ${allowlist.length}');

  if (hits.isEmpty) {
    stdout.writeln('\nOK — every documented path exists on disk.');
    return;
  }

  stdout.writeln('\n${hits.length} dead reference(s):\n');
  final byFile = <String, List<_Hit>>{};
  for (final hit in hits) {
    byFile.putIfAbsent(hit.docFile, () => <_Hit>[]).add(hit);
  }
  for (final entry in byFile.entries) {
    stdout.writeln(entry.key);
    for (final hit in entry.value) {
      stdout.writeln('  ${hit.docFile}:${hit.line}  [${hit.kind}] '
          '${hit.reference}');
    }
    stdout.writeln('');
  }

  stdout.writeln(
    'Each one is either drift (fix the doc) or a path that is correctly\n'
    'absent — generated, gitignored, or a file the reader is told to create.\n'
    'For the second case add it to tools/docs_check/allowlist.txt WITH the\n'
    'reason; an unexplained entry is how this check stops being worth running.',
  );
  if (verbose) {
    stdout.writeln('\nCopy-paste candidates for the allowlist:');
    final unique = hits.map((h) => h.reference.split(' -> ').last).toSet();
    for (final ref in unique.toList()..sort()) {
      stdout.writeln(ref);
    }
  }
  exit(1);
}

final _usage = '''
Verify that every path the documentation names exists in this repository.

  dart tools/docs_check/check.dart [--verbose]

Checks every Markdown file in the repository (skipping ${_skippedDirs.join(', ')}):
  * backticked spans beginning with a real top-level directory
  * markdown links, resolved relative to the file containing them

Known-absent paths belong in tools/docs_check/allowlist.txt, one per line,
with a `#` comment saying why. Exit 1 on any unexplained dead reference.
''';

/// Windows hands back `\` separators; every path this tool compares, prints or
/// looks up in the allowlist is POSIX, so normalise once at the boundary.
String _posix(String path) => path.replaceAll('\\', '/');

String _findRepoRoot() {
  var dir = Directory(p.dirname(Platform.script.toFilePath())).absolute;
  while (true) {
    final isGitRoot = Directory(p.join(dir.path, '.git')).existsSync();
    final isRepoRoot = File(p.join(dir.path, 'pubspec.yaml')).existsSync() &&
        Directory(p.join(dir.path, 'tools')).existsSync();
    if (isGitRoot || isRepoRoot) {
      return dir.path;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) return Directory.current.path;
    dir = parent;
  }
}

Set<String> _readAllowlist(String repoRoot) {
  final file = File(p.join(repoRoot, 'tools', 'docs_check', 'allowlist.txt'));
  if (!file.existsSync()) return <String>{};
  return file
      .readAsLinesSync()
      .map((l) => l.split('#').first.trim())
      .where((l) => l.isNotEmpty)
      .toSet();
}

List<File> _collectDocs(String repoRoot) {
  final out = <File>[];
  void walk(Directory dir) {
    for (final entity in dir.listSync(followLinks: false)) {
      if (entity is Directory) {
        if (_skippedDirs.contains(p.basename(entity.path))) continue;
        walk(entity);
      } else if (entity is File && entity.path.endsWith('.md')) {
        out.add(entity);
      }
    }
  }

  walk(Directory(repoRoot));
  out.sort((a, b) => a.path.compareTo(b.path));
  return out;
}

bool _isExternal(String target) =>
    target.startsWith('http://') ||
    target.startsWith('https://') ||
    target.startsWith('mailto:') ||
    target.startsWith('#');

/// Strips the decoration a path picks up in prose and returns `null` when the
/// span is plainly not a path at all.
String? _normalisePath(String raw) {
  var ref = raw;
  // `platform/kernel/` and `platform/kernel` are the same thing.
  while (ref.endsWith('/')) {
    ref = ref.substring(0, ref.length - 1);
  }
  if (ref.isEmpty) return null;
  // A shell line, not a path: `dart tools/foo.dart`, `cd apps/mobile && flutter test`.
  if (ref.contains(' ')) return null;
  // A set of paths is `_asPattern`'s job, checked before this is called.
  if (ref.contains('*') || ref.contains('{') || ref.contains('<')) return null;
  return ref;
}

/// A span that names a *set* of paths — `modules/<name>/feature/`,
/// `platform/*/pubspec.yaml`, `modules/<m>/{domain,data}/lib` — returned with
/// its trailing slash removed, or null for an ordinary path or a non-path.
///
/// These used to be skipped outright, on the reasoning that a placeholder
/// names nothing in particular. It names *something*, though: at least one
/// real path must fit it. The relayout rewrote `packages/domain/<name>/` as
/// `modules/*/domain/<name>/` in 42 places — shapes no directory in the repo
/// has — and all of them passed, because this check looked away from exactly
/// the kind of reference a mechanical rewrite gets wrong.
///
/// The limit, stated so nobody over-trusts it: a placeholder in the **last**
/// segment matches any child, so `modules/*/domain/<name>` still passes
/// (`modules/auth/domain/lib` fits it). Anything with a fixed segment after
/// the placeholder — `…/<f>/l10n.yaml`, `…/<name>/lib` — is caught.
String? _asPattern(String raw) {
  if (raw.contains(' ')) return null;
  if (!raw.contains('<') && !raw.contains('*') && !raw.contains('{')) {
    return null;
  }
  var ref = raw;
  while (ref.endsWith('/')) {
    ref = ref.substring(0, ref.length - 1);
  }
  return ref.isEmpty ? null : ref;
}

/// True when at least one path in the repository fits [pattern].
///
/// `<anything>` is a placeholder the reader fills in, so it matches like `*`.
/// Braces and `**` are handled by `package:glob` itself.
bool _matchesSomething(String repoRoot, String pattern) {
  final globbable = pattern.replaceAll(RegExp(r'<[^<>]*>'), '*');
  try {
    return Glob(globbable).listSync(root: repoRoot).isNotEmpty;
  } on FileSystemException {
    // A fixed directory component that does not exist — nothing can match.
    return false;
  }
}

bool _looksLikeRepoPath(String ref) =>
    _topLevelDirs.any((d) => ref.startsWith(d));

bool _exists(String repoRoot, String ref) {
  final full = p.join(repoRoot, ref);
  return File(full).existsSync() || Directory(full).existsSync();
}
