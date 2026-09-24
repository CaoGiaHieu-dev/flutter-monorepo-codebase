import 'dart:io';

import 'package:path/path.dart' as p;

/// Stale-translation tracking for `docs/vi/**.md` — advisory, never failing.
///
/// Parity (`parity.dart`) proves a translation has the *shape* of its
/// original; it cannot see a paragraph rewritten in English and left as it
/// was in Vietnamese. What can see it is git: a translation records the
/// English commit it was synced to, and any later commit touching the
/// English file means the translation may be behind.
///
/// The record is a stamp on the first line of the Vietnamese file:
///
///     <!-- translated-from: docs/en/guides/01_x.md@1a2b3c4 -->
///
/// An HTML comment, so it renders as nothing. `--stamp-translations` writes
/// it (the English file's current last-commit short SHA); a translation is
/// stale when `git rev-list <sha>..HEAD -- <en>` is non-empty.

final _stamp = RegExp(
  r'^<!--\s*translated-from:\s*(\S+?)@([0-9a-fA-F]{4,40})\s*-->\s*$',
);

/// The stamp line for [enPath] at [sha].
String stampLine(String enPath, String sha) =>
    '<!-- translated-from: $enPath@$sha -->';

class TranslationStamp {
  TranslationStamp(this.viPath, this.enPath, this.sha);

  final String viPath;
  final String enPath;
  final String sha;
}

/// The stamp on the first line of [viPath] (repo-relative), or null.
TranslationStamp? readStamp(String repoRoot, String viPath) {
  final file = File(p.join(repoRoot, viPath));
  if (!file.existsSync()) return null;
  final content = file.readAsStringSync();
  final end = content.indexOf('\n');
  final first = (end == -1 ? content : content.substring(0, end)).trimRight();
  final m = _stamp.firstMatch(first);
  return m == null ? null : TranslationStamp(viPath, m.group(1)!, m.group(2)!);
}

/// Every Vietnamese document among [docs] (repo-relative POSIX paths).
List<String> viDocs(Iterable<String> docs) =>
    docs.where((d) => d.startsWith('docs/vi/') && d.endsWith('.md')).toList()
      ..sort();

/// The English original [viPath] translates: its stamp's path when it has
/// one, else the mirror path under `docs/en/`.
String englishSourceOf(String repoRoot, String viPath) =>
    readStamp(repoRoot, viPath)?.enPath ??
    'docs/en/${viPath.substring('docs/vi/'.length)}';

/// Runs git in [repoRoot]; null when git is not installed.
ProcessResult? _git(String repoRoot, List<String> args) {
  try {
    return Process.runSync('git', args, workingDirectory: repoRoot);
  } on ProcessException {
    return null;
  }
}

/// Whether [repoRoot] is inside a git work tree with at least one commit.
bool gitHistoryAvailable(String repoRoot) {
  final r = _git(repoRoot, ['rev-parse', '--verify', '-q', 'HEAD']);
  return r != null && r.exitCode == 0;
}

/// Short SHA of the last commit touching [path], or null when none does.
String? lastCommitOf(String repoRoot, String path) {
  final r = _git(repoRoot, ['log', '-1', '--format=%h', '--', path]);
  if (r == null || r.exitCode != 0) return null;
  final sha = '${r.stdout}'.trim();
  return sha.isEmpty ? null : sha;
}

class StaleTranslation {
  StaleTranslation(this.stamp, this.commits, this.latest);

  final TranslationStamp stamp;

  /// Commits touching the English file since the stamped one.
  final int commits;

  /// The English file's last commit now.
  final String? latest;
}

class StaleReport {
  StaleReport({
    required this.gitAvailable,
    required this.stamped,
    required this.unstamped,
    required this.stale,
    required this.unknownCommit,
    required this.missingSource,
  });

  final bool gitAvailable;
  final List<TranslationStamp> stamped;
  final List<String> unstamped;
  final List<StaleTranslation> stale;

  /// Stamps whose commit is not in this checkout (a shallow clone, or a
  /// rewritten history) — staleness cannot be decided.
  final List<TranslationStamp> unknownCommit;

  /// Stamps naming an English file that no longer exists.
  final List<TranslationStamp> missingSource;
}

/// Compares every stamp in [vis] with the English file's git history.
StaleReport staleTranslations(String repoRoot, List<String> vis) {
  final stamped = <TranslationStamp>[];
  final unstamped = <String>[];
  for (final vi in vis) {
    final stamp = readStamp(repoRoot, vi);
    if (stamp == null) {
      unstamped.add(vi);
    } else {
      stamped.add(stamp);
    }
  }

  final git = gitHistoryAvailable(repoRoot);
  final stale = <StaleTranslation>[];
  final unknown = <TranslationStamp>[];
  final missing = <TranslationStamp>[];
  if (git) {
    for (final stamp in stamped) {
      if (!File(p.join(repoRoot, stamp.enPath)).existsSync()) {
        missing.add(stamp);
        continue;
      }
      final known = _git(repoRoot, [
        'cat-file',
        '-e',
        '${stamp.sha}^{commit}',
      ]);
      if (known == null || known.exitCode != 0) {
        unknown.add(stamp);
        continue;
      }
      final count = _git(repoRoot, [
        'rev-list',
        '--count',
        '${stamp.sha}..HEAD',
        '--',
        stamp.enPath,
      ]);
      final n = int.tryParse('${count?.stdout}'.trim()) ?? 0;
      if (n > 0) {
        stale.add(
          StaleTranslation(stamp, n, lastCommitOf(repoRoot, stamp.enPath)),
        );
      }
    }
  }
  return StaleReport(
    gitAvailable: git,
    stamped: stamped,
    unstamped: unstamped,
    stale: stale,
    unknownCommit: unknown,
    missingSource: missing,
  );
}

/// Outcome of stamping one Vietnamese file.
enum StampOutcome { written, unchanged, noSource, uncommittedSource }

/// Writes (or replaces) the stamp on [viPath] with the last commit of its
/// English source. The rest of the file is kept byte for byte.
(StampOutcome, String en, String? sha) stampTranslation(
  String repoRoot,
  String viPath,
) {
  final en = englishSourceOf(repoRoot, viPath);
  if (!File(p.join(repoRoot, en)).existsSync()) {
    return (StampOutcome.noSource, en, null);
  }
  final sha = lastCommitOf(repoRoot, en);
  if (sha == null) return (StampOutcome.uncommittedSource, en, null);

  final file = File(p.join(repoRoot, viPath));
  final content = file.readAsStringSync();
  final line = stampLine(en, sha);
  final String updated;
  if (readStamp(repoRoot, viPath) != null) {
    final end = content.indexOf('\n');
    // Keep the original line ending, `\r\n` included.
    final restStart = end > 0 && content[end - 1] == '\r' ? end - 1 : end;
    final rest = end == -1 ? '' : content.substring(restStart);
    updated = '$line$rest';
  } else {
    final eol = content.contains('\r\n') ? '\r\n' : '\n';
    updated = '$line$eol$content';
  }
  if (updated == content) return (StampOutcome.unchanged, en, sha);
  file.writeAsStringSync(updated);
  return (StampOutcome.written, en, sha);
}
