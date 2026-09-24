import 'dart:io';

import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'parity.dart';
import 'rule_ids.dart';
import 'translations.dart';

/// Mechanical accuracy check for the Markdown documentation.
///
/// Prose rots silently: a package gets renamed, a file moves, and the guide
/// telling a newcomer to open it keeps saying the old name. `flutter analyze`
/// cannot see a sentence, so this is the only thing standing between the docs
/// and quiet decay.
///
/// Two classes of reference are verified:
///
///   1. **Backticked repo paths** — `` `platform/foundation/kernel/lib` `` —
///      any backtick span that starts with a real top-level directory of this
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
/// Two kinds of reference are reported without failing the run:
///
///   * **Placeholders.** A span with a `<…>` segment (`modules/<owner>/feature/…`)
///     is a template the reader fills in, not a reference to a file. Only its
///     literal part — the segments before the first placeholder — must exist.
///   * **Removed samples.** `tools/sample_cleanup/remove_sample.dart` deletes
///     a sample bundle's packages but leaves `tools/sample_manifest.yaml`
///     untouched, on purpose: the manifest is how this check knows a path
///     belonged to a sample. A bundle whose packages are *all* gone from disk
///     (bar a `modules/<id>/api` package remove_sample kept because another
///     package still imports it) is "removed", and a dead reference inside it (its package paths, the
///     emptied `modules/<id>` parent, its `orphaned_contracts`) is summarised
///     per bundle as expected fallout rather than drift. Delete the bundle's
///     entry from the manifest once the docs are updated — or never, if you
///     do not mind the note.
///
/// A second check runs on the same documents: **en ↔ vi parity**
/// (`parity.dart`). Every `docs/en/**.md` with a `docs/vi` counterpart, and
/// every `<name>.md` with a `<name>.vi.md` beside it, must have the same
/// number of headings per level, fenced code blocks and table rows in both
/// languages. Intentional differences are listed, with a reason, in
/// `parity_allowlist.txt` next to this file.
///
/// A third, **RULE-ID citations** (`rule_ids.dart`): every `RULE-NN` token in
/// any document must be a row ID of the registry table in
/// `docs/en/reference/01_rules.md`, and the Vietnamese registry must define
/// the same IDs. Skipped, with an INFO line, while neither registry has a row.
///
/// Finally, **stale translations** (`translations.dart`) — advisory only. A
/// `docs/vi` file may carry a first-line stamp naming the English commit it
/// was synced to; a stamp older than the English file's last commit is
/// counted in one INFO line (`--stale-translations` lists them), and
/// `--stamp-translations` writes the stamps.
///
/// Exit code 0 = clean, 1 = at least one dead reference, unexplained parity
/// mismatch or unknown RULE-ID, 64 = bad argument. Stale translations never
/// change the exit code.

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

/// A sample bundle from `tools/sample_manifest.yaml` whose packages are all
/// absent from disk — what `remove_sample.dart <bundle> --apply` leaves.
class _RemovedBundle {
  _RemovedBundle(this.name, this.paths);

  final String name;

  /// Repo-relative paths that went with the bundle: its package directories,
  /// a `modules/<id>` parent that no longer exists, and its
  /// `orphaned_contracts`.
  final List<String> paths;

  /// Whether [ref] points into the removed bundle. A brace pattern
  /// (`modules/auth/{domain,data,feature}`) is covered when every
  /// alternative is — which matters once a kept API package keeps
  /// `modules/<id>` itself on disk.
  bool covers(String ref) {
    final brace = RegExp(r'\{([^{}]*)\}').firstMatch(ref);
    if (brace != null) {
      return brace
          .group(1)!
          .split(',')
          .every(
            (alt) => covers(ref.replaceRange(brace.start, brace.end, alt)),
          );
    }
    return paths.any((path) => ref == path || ref.startsWith('$path/'));
  }
}

void main(List<String> args) {
  if (args.contains('--help') || args.contains('-h')) {
    stdout.writeln(_usage);
    return;
  }
  // A misspelt flag (`--verbos`) used to be ignored and the run reported as
  // if it had been asked for; anything unrecognised is a usage error.
  const known = {
    '--verbose',
    '-v',
    '--stale-translations',
    '--stamp-translations',
  };
  final stamp = args.contains('--stamp-translations');
  final unknown = args
      .where((a) => !known.contains(a) && (a.startsWith('-') || !stamp))
      .toList();
  if (unknown.isNotEmpty) {
    stderr.writeln('docs_check: unknown argument(s): ${unknown.join(' ')}');
    stderr.writeln(_usage);
    exit(64);
  }
  if (stamp && args.contains('--stale-translations')) {
    stderr.writeln(
      'docs_check: --stamp-translations and --stale-translations are '
      'separate runs; pass one.',
    );
    exit(64);
  }

  final repoRoot = _findRepoRoot();
  final verbose = args.contains('--verbose') || args.contains('-v');

  if (stamp) {
    exit(
      _stampTranslations(
        repoRoot,
        args.where((a) => !a.startsWith('-')).toList(),
      ),
    );
  }

  final allowlist = _readAllowlist(repoRoot);
  final removedBundles = _removedSampleBundles(repoRoot);
  final docs = _collectDocs(repoRoot);

  if (docs.isEmpty) {
    stderr.writeln('docs_check: no Markdown files found under $repoRoot');
    exit(1);
  }

  final hits = <_Hit>[];
  final sampleHits = <String, List<_Hit>>{};
  var checked = 0;

  /// Files [hit] under the removed bundle [path] lies in, else as drift.
  /// A glob [pattern] also counts as inside a bundle when the bundle covers
  /// the pattern itself (a brace list of its removed layers).
  void report(_Hit hit, String path, {String? pattern}) {
    for (final bundle in removedBundles) {
      if (bundle.covers(path) || (pattern != null && bundle.covers(pattern))) {
        sampleHits.putIfAbsent(bundle.name, () => <_Hit>[]).add(hit);
        return;
      }
    }
    hits.add(hit);
  }

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
          report(
            _Hit(relDoc, i + 1, pattern, 'pattern'),
            _literalPrefix(pattern),
            pattern: pattern,
          );
          continue;
        }
        final ref = _normalisePath(raw);
        if (ref == null) continue;
        if (!_looksLikeRepoPath(ref)) continue;
        checked++;
        if (allowlist.contains(ref)) continue;
        if (_exists(repoRoot, ref)) continue;
        report(_Hit(relDoc, i + 1, ref, 'path'), ref);
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
        report(_Hit(relDoc, i + 1, '$target -> $resolved', 'link'), resolved);
      }
    }
  }

  stdout.writeln('Docs accuracy check');
  stdout.writeln('  documents : ${docs.length}');
  stdout.writeln('  references: $checked');
  stdout.writeln('  allowlist : ${allowlist.length}');

  if (sampleHits.isNotEmpty) {
    stdout.writeln('');
    for (final entry in sampleHits.entries) {
      final files = entry.value.map((h) => h.docFile).toSet();
      stdout.writeln(
        'INFO: ${entry.value.length} reference(s) in ${files.length} '
        'document(s) point to removed sample bundle "${entry.key}" — expected '
        'after remove_sample; update the docs at your leisure.',
      );
      if (verbose) {
        for (final hit in entry.value) {
          stdout.writeln(
            '  ${hit.docFile}:${hit.line}  [${hit.kind}] ${hit.reference}',
          );
        }
      }
    }
    if (!verbose) {
      stdout.writeln(
        '      (--verbose lists them; they do not fail this check)',
      );
    }
  }

  final relDocs = [
    for (final doc in docs)
      p.posix.relative(_posix(doc.path), from: _posix(repoRoot)),
  ];
  final parityFailed = _reportParity(repoRoot, docs, verbose);
  final rulesFailed = _reportRuleIds(repoRoot, relDocs);
  _reportStaleTranslations(
    repoRoot,
    relDocs,
    detailed: args.contains('--stale-translations'),
    verbose: verbose,
  );

  if (hits.isEmpty) {
    stdout.writeln(
      sampleHits.isEmpty
          ? '\nOK — every documented path exists on disk.'
          : '\nOK — every documented path outside the removed samples exists '
                'on disk.',
    );
    if (parityFailed || rulesFailed) exit(1);
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
      stdout.writeln(
        '  ${hit.docFile}:${hit.line}  [${hit.kind}] '
        '${hit.reference}',
      );
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

final _usage =
    '''
Verify that every path the documentation names exists in this repository.

  dart tools/docs_check/check.dart [--verbose] [--stale-translations]
  dart tools/docs_check/check.dart --stamp-translations [<docs/vi file>...]

Checks every Markdown file in the repository (skipping ${_skippedDirs.join(', ')}):
  * backticked spans beginning with a real top-level directory
  * markdown links, resolved relative to the file containing them

A span with a <placeholder> segment is a template: only the part before the
first placeholder must exist. A dead reference inside a sample bundle that
remove_sample.dart has removed (every package of the bundle absent, per
tools/sample_manifest.yaml — a module API package remove_sample kept because
something still imports it aside) is summarised as INFO and does not fail the
run.

Known-absent paths belong in tools/docs_check/allowlist.txt, one per line,
with a `#` comment saying why.

It also checks en <-> vi parity: every docs/en/**.md with a docs/vi
counterpart, and every <name>.md with a <name>.vi.md beside it, must have the
same count of headings per level (h1-h6), fenced code blocks (code-blocks)
and table rows (table-rows). An intentional difference goes in
tools/docs_check/parity_allowlist.txt as "<english file> <metric>" (or "*")
with a `#` reason.

It also checks RULE-ID citations: every RULE-<digits> token in any Markdown
file must be a row ID of the registry table in docs/en/reference/01_rules.md
(rows look like "| RULE-01 | ..."), no ID may be defined twice, and
docs/vi/reference/01_rules.md must define exactly the same IDs. While neither
registry has a row the check is skipped with an INFO line.

Stale translations (advisory — never changes the exit code). A docs/vi file
may start with the stamp
  <!-- translated-from: docs/en/<path>.md@<short-sha> -->
recording the English commit it was synced to. When any stamp exists, a
normal run prints one INFO line counting the translations whose English
source has commits after the stamped one.

  dart tools/docs_check/check.dart --stale-translations
      Also lists every stale translation (and, with --verbose, every
      unstamped docs/vi file).
  dart tools/docs_check/check.dart --stamp-translations [<docs/vi file>...]
      Writes or updates the stamp to the English file's current last commit
      (`git log -1 --format=%h -- <en>`), then exits without checking.
      Pass the files you just synced; with no file, every docs/vi file is
      stamped — which marks every translation as current, so do that only
      when adopting stamps. Commit the English change first: a stamp can
      only name a commit that exists.

Exit 1 on any unexplained dead reference, parity mismatch or RULE-ID problem,
64 on an unknown argument.
''';

/// `--stamp-translations`: stamps [paths] (every docs/vi file when empty).
/// Returns the exit code.
int _stampTranslations(String repoRoot, List<String> paths) {
  if (!gitHistoryAvailable(repoRoot)) {
    stderr.writeln(
      'docs_check: --stamp-translations needs a git checkout with at least '
      'one commit ($repoRoot).',
    );
    return 1;
  }
  final root = _posix(repoRoot);
  final List<String> targets;
  if (paths.isEmpty) {
    targets = viDocs([
      for (final doc in _collectDocs(repoRoot))
        p.posix.relative(_posix(doc.path), from: root),
    ]);
  } else {
    targets = [];
    for (final raw in paths) {
      // Relative to the working directory first, then to the repo root.
      final candidates = [
        p.posix.normalize(
          p.posix.join(_posix(Directory.current.path), _posix(raw)),
        ),
        p.posix.normalize(p.posix.join(root, _posix(raw))),
      ];
      String? rel;
      for (final c in candidates) {
        final r = p.posix.relative(c, from: root);
        if (File(c).existsSync() && !r.startsWith('..')) {
          rel = r;
          break;
        }
      }
      if (rel == null || !rel.startsWith('docs/vi/') || !rel.endsWith('.md')) {
        stderr.writeln('docs_check: not a docs/vi Markdown file: $raw');
        return 64;
      }
      targets.add(rel);
    }
  }

  var written = 0;
  var unchanged = 0;
  var skipped = 0;
  for (final vi in targets) {
    final (outcome, en, sha) = stampTranslation(repoRoot, vi);
    switch (outcome) {
      case StampOutcome.written:
        written++;
        stdout.writeln('  stamped   $vi  <- $en@$sha');
      case StampOutcome.unchanged:
        unchanged++;
      case StampOutcome.noSource:
        skipped++;
        stdout.writeln('  skipped   $vi  ($en does not exist)');
      case StampOutcome.uncommittedSource:
        skipped++;
        stdout.writeln(
          '  skipped   $vi  ($en has no commit yet — commit it, then stamp)',
        );
    }
  }
  stdout.writeln(
    'Translation stamps: $written written, $unchanged already current, '
    '$skipped skipped.',
  );
  return 0;
}

/// Runs the RULE-ID citation check over [docs] and prints its section.
/// Returns whether it failed.
bool _reportRuleIds(String repoRoot, List<String> docs) {
  final result = checkRuleIds(repoRoot, docs);
  stdout.writeln('');
  stdout.writeln('RULE-ID citations');
  if (!result.registryFound) {
    stdout.writeln(
      'INFO: no "| RULE-NN |" registry row in $enRegistry or $viRegistry '
      'yet — citation check skipped.',
    );
    return false;
  }
  stdout.writeln('  registry  : ${result.registered.length} rule(s)');
  stdout.writeln('  citations : ${result.citations}');
  if (result.problems.isEmpty) {
    stdout.writeln('OK — every cited RULE-ID is defined in the registry.');
    return false;
  }
  stdout.writeln('\n${result.problems.length} RULE-ID problem(s):\n');
  for (final problem in result.problems) {
    stdout.writeln('  $problem');
  }
  stdout.writeln(
    '\nCite only IDs that have a row in the registry table of $enRegistry, '
    'and keep\n$viRegistry defining the same IDs. A rule that is retired '
    'keeps its row (marked\nretired) so old citations still resolve; IDs are '
    'never reused.',
  );
  return true;
}

/// Prints the stale-translation summary: one INFO line when any stamp
/// exists, or the full list when [detailed]. Never fails the run.
void _reportStaleTranslations(
  String repoRoot,
  List<String> docs, {
  required bool detailed,
  required bool verbose,
}) {
  final vis = viDocs(docs);
  final anyStamp = vis.any((vi) => readStamp(repoRoot, vi) != null);
  if (!anyStamp && !detailed) return;

  final report = staleTranslations(repoRoot, vis);
  stdout.writeln('');
  stdout.writeln('Stale translations (advisory)');
  if (!report.gitAvailable) {
    stdout.writeln(
      'INFO: no git history here — translation stamps not compared.',
    );
    return;
  }
  final extras = [
    if (report.missingSource.isNotEmpty)
      '${report.missingSource.length} name an English file that no longer '
          'exists',
    if (report.unknownCommit.isNotEmpty)
      '${report.unknownCommit.length} name a commit not in this checkout '
          '(shallow clone?)',
  ];
  stdout.writeln(
    'INFO: ${report.stale.length} of ${report.stamped.length} stamped '
    'translation(s) are behind their English source'
    '${extras.isEmpty ? '' : '; ${extras.join('; ')}'}'
    '${report.unstamped.isEmpty ? '' : ' (${report.unstamped.length} docs/vi file(s) unstamped)'}.',
  );
  if (!detailed) {
    if (report.stale.isNotEmpty || extras.isNotEmpty) {
      stdout.writeln('      (--stale-translations lists them)');
    }
    return;
  }
  for (final s in report.stale) {
    stdout.writeln(
      '  ${s.stamp.viPath}  <- ${s.stamp.enPath}: ${s.commits} commit(s) '
      'since ${s.stamp.sha} (now ${s.latest ?? '?'})',
    );
  }
  for (final s in report.missingSource) {
    stdout.writeln('  ${s.viPath}  <- ${s.enPath}: English file not found');
  }
  for (final s in report.unknownCommit) {
    stdout.writeln(
      '  ${s.viPath}  <- ${s.enPath}: commit ${s.sha} not in this checkout',
    );
  }
  if (verbose) {
    for (final vi in report.unstamped) {
      stdout.writeln('  unstamped: $vi');
    }
  }
  if (report.stale.isNotEmpty) {
    stdout.writeln(
      '\nRe-sync each listed translation from `git diff <sha> -- <en file>`, '
      'then\ndart tools/docs_check/check.dart --stamp-translations '
      '<docs/vi file>...',
    );
  }
}

/// Runs the en <-> vi parity check over [docs] and prints its section.
/// Returns whether it failed.
bool _reportParity(String repoRoot, List<File> docs, bool verbose) {
  final file = File(
    p.join(repoRoot, 'tools', 'docs_check', 'parity_allowlist.txt'),
  );
  final allowlist = ParityAllowlist.parse(
    file.existsSync() ? file.readAsStringSync() : '',
  );
  final rel = [
    for (final doc in docs)
      p.posix.relative(_posix(doc.path), from: _posix(repoRoot)),
  ];
  final result = checkParity(repoRoot, rel, allowlist);

  stdout.writeln('');
  stdout.writeln('en <-> vi parity');
  stdout.writeln('  pairs     : ${result.pairs}');
  stdout.writeln('  allowlist : ${allowlist.entries.length}');
  if (verbose) {
    for (final m in result.allowed) {
      stdout.writeln('  allowed   : $m');
    }
  }
  for (final entry in result.stale) {
    stdout.writeln(
      'WARN: parity_allowlist.txt entry "$entry" matches no difference any '
      'more — delete it.',
    );
  }
  if (allowlist.errors.isNotEmpty) {
    stdout.writeln('\nparity_allowlist.txt is malformed:');
    for (final error in allowlist.errors) {
      stdout.writeln('  $error');
    }
  }
  if (result.mismatches.isEmpty) {
    if (allowlist.errors.isEmpty) {
      stdout.writeln(
        'OK — every translated document has the shape of its original.',
      );
    }
    return allowlist.errors.isNotEmpty;
  }

  stdout.writeln('\n${result.mismatches.length} parity mismatch(es):\n');
  for (final m in result.mismatches) {
    stdout.writeln('  $m');
  }
  stdout.writeln(
    '\nA heading, code block or table row exists in one language only. '
    'Translate\nit across, or — when the difference is intentional — add '
    '"<english file> <metric>"\nto tools/docs_check/parity_allowlist.txt '
    'WITH the reason.',
  );
  return true;
}

/// Windows hands back `\` separators; every path this tool compares, prints or
/// looks up in the allowlist is POSIX, so normalise once at the boundary.
String _posix(String path) => path.replaceAll('\\', '/');

String _findRepoRoot() {
  var dir = Directory(p.dirname(Platform.script.toFilePath())).absolute;
  while (true) {
    final isGitRoot = Directory(p.join(dir.path, '.git')).existsSync();
    final isRepoRoot =
        File(p.join(dir.path, 'pubspec.yaml')).existsSync() &&
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
  // `platform/ui/ui_kit/` and `platform/ui/ui_kit` are the same thing.
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
/// `platform/*/*/pubspec.yaml`, `modules/<m>/{domain,data}/lib` — returned with
/// its trailing slash removed, or null for an ordinary path or a non-path.
///
/// These used to be skipped outright. A glob (`*`, `{a,b}`) names
/// *something*, though: at least one real path must fit it, which is what
/// catches a mechanical rewrite pointing at a shape no directory has.
///
/// A `<placeholder>` is different. It stands for a name the reader has not
/// chosen yet — `modules/<owner>/feature/lib/src/handlers` describes where
/// *your* module puts its handlers — so it is a template, not a reference.
/// Demanding that some existing module already had that folder made the check
/// fail whenever the only one that did was a removed sample. The pattern is
/// therefore cut at its first `<…>` segment and only the literal part before
/// it must match: `packages/domain/<name>` is still caught (`packages/domain`
/// is gone), `modules/<owner>/…` passes because `modules` exists. The price,
/// stated so nobody over-trusts it: a wrong fixed segment *after* a
/// placeholder (`modules/<m>/featur/…`) is no longer seen.
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
  final checked = _beforePlaceholder(pattern);
  if (!checked.contains('*') && !checked.contains('{')) {
    return _exists(repoRoot, checked);
  }
  try {
    return Glob(checked).listSync(root: repoRoot).isNotEmpty;
  } on FileSystemException {
    // A fixed directory component that does not exist — nothing can match.
    return false;
  }
}

/// [pattern] up to (not including) its first `<placeholder>` segment —
/// `modules/<owner>/feature` -> `modules`; unchanged when it has none.
String _beforePlaceholder(String pattern) {
  final segments = pattern.split('/');
  final cut = segments.indexWhere((s) => s.contains('<'));
  return cut < 0 ? pattern : segments.take(cut).join('/');
}

/// [pattern] up to its first segment holding `<`, `*` or `{` — the fixed
/// directory every path it names lies under.
String _literalPrefix(String pattern) {
  final segments = pattern.split('/');
  final cut = segments.indexWhere(
    (s) => s.contains('<') || s.contains('*') || s.contains('{'),
  );
  return cut < 0 ? pattern : segments.take(cut).join('/');
}

/// Every sample bundle in `tools/sample_manifest.yaml` whose packages are
/// all absent from disk — a module API package (`modules/<id>/api`) aside.
///
/// `remove_sample.dart` never edits the manifest, so after `--apply` the
/// bundle definition is still here while its packages are not — which is the
/// whole signal. The exception is the module's API package: `remove_sample`
/// keeps it while another package still imports it, so a bundle whose only
/// survivor is its `api` directory counts as removed (the API's own paths
/// still exist and are checked as usual). Any other package left on disk
/// means the bundle is not removed: a half-deleted bundle is drift, and its
/// dead references fail as usual.
List<_RemovedBundle> _removedSampleBundles(String repoRoot) {
  final file = File(p.join(repoRoot, 'tools', 'sample_manifest.yaml'));
  if (!file.existsSync()) return const [];
  final Object? doc;
  try {
    doc = loadYaml(file.readAsStringSync());
  } on YamlException catch (e) {
    stderr.writeln(
      'docs_check: tools/sample_manifest.yaml is not valid YAML ($e) — '
      'references to removed samples are reported as dead.',
    );
    return const [];
  }
  if (doc is! Map) return const [];
  final packages = doc['packages'];
  final bundles = doc['bundles'];
  if (packages is! Map || bundles is! Map) return const [];

  final out = <_RemovedBundle>[];
  bundles.forEach((name, value) {
    if (value is! Map || value['packages'] is! List) return;
    final dirs = <String>[
      for (final pkg in value['packages'] as List)
        if (packages[pkg] case {'path': final String path}) path,
    ];
    bool isApi(String dir) =>
        dir.startsWith('modules/') && p.posix.basename(dir) == 'api';
    final required = dirs.where((d) => !isApi(d)).toList();
    if (required.isEmpty || required.any((d) => _exists(repoRoot, d))) return;
    out.add(
      _RemovedBundle('$name', [
        ...required,
        // `modules/auth` goes too once its last layer is removed.
        for (final dir in dirs)
          if (dir.startsWith('modules/') &&
              !_exists(repoRoot, p.posix.dirname(dir)))
            p.posix.dirname(dir),
        if (value['orphaned_contracts'] case final List<Object?> contracts)
          for (final c in contracts)
            if (c is String) c,
      ]),
    );
  });
  return out;
}

bool _looksLikeRepoPath(String ref) =>
    _topLevelDirs.any((d) => ref.startsWith(d));

bool _exists(String repoRoot, String ref) {
  final full = p.join(repoRoot, ref);
  return File(full).existsSync() || Directory(full).existsSync();
}
