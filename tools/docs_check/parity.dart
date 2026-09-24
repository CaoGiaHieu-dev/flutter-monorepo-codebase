import 'dart:io';

import 'package:path/path.dart' as p;

/// English ↔ Vietnamese structural parity for the translated documentation.
///
/// The Vietnamese tree mirrors the English one file for file, and the two
/// drift the same way prose always does: a section, a command block or a
/// table row gets added to one language and never reaches the other. A
/// translation cannot be diffed word for word, but its *shape* can: the same
/// document has the same number of headings at each level, the same number
/// of fenced code blocks and the same number of table rows in both languages.
///
/// Pairs compared:
///
///   * `docs/en/<path>.md` with `docs/vi/<path>.md`, when both exist;
///   * `<dir>/<name>.md` with `<dir>/<name>.vi.md` anywhere else
///     (`README.md` / `README.vi.md`, `tools/code_review/README.md`, …).
///
/// Intentional differences go in `tools/docs_check/parity_allowlist.txt`,
/// one `<english file> <metric>` per line with a `#` reason (`*` for every
/// metric). An entry with no reason is refused: an unexplained exemption is
/// how a check stops meaning anything.

/// The metrics compared, in report order.
const parityMetrics = [
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'code-blocks',
  'table-rows',
];

/// One document's shape: [parityMetrics] -> count.
Map<String, int> documentShape(String markdown) {
  final counts = {for (final m in parityMetrics) m: 0};
  final heading = RegExp(r'^(#{1,6})(?:\s|$)');
  final fenceOpen = RegExp(r'^\s*(`{3,}|~{3,})');
  String? fence;

  for (final raw in markdown.split('\n')) {
    final line = raw.trimRight();
    // Quoted content counts too: a table or a code block inside a
    // `> [!NOTE]` is still one the other language must have.
    final content = line.replaceFirst(RegExp(r'^\s*(?:>\s?)+'), '');
    final quoted = content != line;
    if (fence != null) {
      // A closing fence is the same character, at least as long, and
      // nothing after it.
      final trimmed = content.trimLeft();
      if (trimmed.startsWith(fence) &&
          trimmed.replaceAll(fence[0], '').trim().isEmpty) {
        fence = null;
      }
      continue;
    }
    final open = fenceOpen.firstMatch(content);
    if (open != null) {
      fence = open.group(1);
      counts['code-blocks'] = counts['code-blocks']! + 1;
      continue;
    }
    final h = heading.firstMatch(content);
    if (h != null && !quoted) {
      final key = 'h${h.group(1)!.length}';
      counts[key] = counts[key]! + 1;
      continue;
    }
    if (content.trimLeft().startsWith('|')) {
      counts['table-rows'] = counts['table-rows']! + 1;
    }
  }
  return counts;
}

/// One metric that differs between a document and its translation.
class ParityMismatch {
  ParityMismatch(this.en, this.vi, this.metric, this.enCount, this.viCount);

  /// Repo-relative, `/`-separated.
  final String en;
  final String vi;
  final String metric;
  final int enCount;
  final int viCount;

  String get key => '$en $metric';

  @override
  String toString() => '$en  $metric: en $enCount vs vi $viCount  ($vi)';
}

/// Every English/Vietnamese pair among [docs] (repo-relative paths).
List<(String en, String vi)> translationPairs(Iterable<String> docs) {
  final all = docs.toSet();
  final pairs = <(String, String)>[];
  for (final doc in all) {
    if (doc.startsWith('docs/en/')) {
      final vi = 'docs/vi/${doc.substring('docs/en/'.length)}';
      if (all.contains(vi)) pairs.add((doc, vi));
    } else if (doc.endsWith('.md') &&
        !doc.endsWith('.vi.md') &&
        !doc.startsWith('docs/vi/')) {
      final vi = '${doc.substring(0, doc.length - 3)}.vi.md';
      if (all.contains(vi)) pairs.add((doc, vi));
    }
  }
  pairs.sort((a, b) => a.$1.compareTo(b.$1));
  return pairs;
}

/// A parsed `parity_allowlist.txt`.
class ParityAllowlist {
  ParityAllowlist(this.entries, this.errors);

  /// `<english file> <metric>` keys; the metric may be `*`.
  final Set<String> entries;

  /// Malformed lines, as messages naming the line.
  final List<String> errors;

  bool covers(ParityMismatch m) =>
      entries.contains(m.key) || entries.contains('${m.en} *');

  static ParityAllowlist parse(String text) {
    final entries = <String>{};
    final errors = <String>[];
    final lines = text.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final hash = line.indexOf('#');
      final body = (hash < 0 ? line : line.substring(0, hash)).trim();
      if (body.isEmpty) continue;
      final reason = hash < 0 ? '' : line.substring(hash + 1).trim();
      final parts = body.split(RegExp(r'\s+'));
      if (parts.length != 2 ||
          !(parts[1] == '*' || parityMetrics.contains(parts[1]))) {
        errors.add(
          'line ${i + 1}: expected "<english file> <metric>" with metric one '
          'of ${parityMetrics.join(', ')} or *, got "$body"',
        );
        continue;
      }
      if (reason.isEmpty) {
        errors.add(
          'line ${i + 1}: "$body" has no reason — add "# why the two '
          'languages legitimately differ here"',
        );
        continue;
      }
      entries.add('${parts[0]} ${parts[1]}');
    }
    return ParityAllowlist(entries, errors);
  }
}

/// The result of comparing every pair under [repoRoot].
class ParityResult {
  ParityResult(this.pairs, this.mismatches, this.allowed, this.stale);

  final int pairs;

  /// Differences the allowlist does not cover — each one fails the run.
  final List<ParityMismatch> mismatches;

  /// Differences the allowlist covers.
  final List<ParityMismatch> allowed;

  /// Allowlist entries that matched nothing: the difference is gone.
  final List<String> stale;
}

ParityResult checkParity(
  String repoRoot,
  Iterable<String> docs,
  ParityAllowlist allowlist,
) {
  final pairs = translationPairs(docs);
  final mismatches = <ParityMismatch>[];
  final allowed = <ParityMismatch>[];
  final used = <String>{};

  for (final (en, vi) in pairs) {
    final enShape = documentShape(
      File(p.join(repoRoot, en)).readAsStringSync(),
    );
    final viShape = documentShape(
      File(p.join(repoRoot, vi)).readAsStringSync(),
    );
    for (final metric in parityMetrics) {
      if (enShape[metric] == viShape[metric]) continue;
      final m = ParityMismatch(
        en,
        vi,
        metric,
        enShape[metric]!,
        viShape[metric]!,
      );
      if (allowlist.covers(m)) {
        allowed.add(m);
        used.add(allowlist.entries.contains(m.key) ? m.key : '$en *');
      } else {
        mismatches.add(m);
      }
    }
  }
  final stale = allowlist.entries.where((e) => !used.contains(e)).toList()
    ..sort();
  return ParityResult(pairs.length, mismatches, allowed, stale);
}
