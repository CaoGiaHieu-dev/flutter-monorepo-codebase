import 'dart:io';

import 'package:path/path.dart' as p;

/// RULE-ID citations: every `RULE-NN` a document cites must be a rule the
/// registry defines.
///
/// The registry is the table in `docs/en/reference/01_rules.md` whose rows
/// start with the ID (`| RULE-01 | … |`). Guides, skills, the review prompt
/// and the agent instructions cite rules by that ID instead of restating
/// them, which only works while every cited ID still exists: a renumbered or
/// deleted rule leaves citations pointing at nothing, and nothing else would
/// notice. The Vietnamese registry (`docs/vi/reference/01_rules.md`) must
/// define exactly the same IDs.
///
/// Until a registry row exists in either language the check is skipped with
/// an INFO line, so the gate can land before the registry does.

const enRegistry = 'docs/en/reference/01_rules.md';
const viRegistry = 'docs/vi/reference/01_rules.md';

/// A registry row: a table row whose first cell is the ID.
final _registryRow = RegExp(r'^\s*\|\s*(RULE-\d+)\s*\|');

/// A citation. `RULE-\d+` rather than exactly two digits, so a typo such as
/// `RULE-7` is reported as unknown instead of silently not matching.
/// A placeholder like `RULE-NN` has no digits and is not a citation.
final _citation = RegExp(r'\bRULE-\d+\b');

class RuleIdResult {
  RuleIdResult({
    required this.registryFound,
    required this.registered,
    required this.citations,
    required this.problems,
  });

  /// Whether either registry has at least one row. When false, nothing
  /// else was checked.
  final bool registryFound;

  /// IDs defined by the English registry.
  final Set<String> registered;

  /// Citations seen across all documents (registry rows included).
  final int citations;

  /// One line per failure, `file:line  message` where a line applies.
  final List<String> problems;
}

/// Registry rows of [rel] as ID -> 1-based lines (more than one line is a
/// duplicate). Empty when the file does not exist.
Map<String, List<int>> _registryRows(String repoRoot, String rel) {
  final file = File(p.join(repoRoot, rel));
  if (!file.existsSync()) return const {};
  final rows = <String, List<int>>{};
  final lines = file.readAsLinesSync();
  for (var i = 0; i < lines.length; i++) {
    final m = _registryRow.firstMatch(lines[i]);
    if (m != null) (rows[m.group(1)!] ??= <int>[]).add(i + 1);
  }
  return rows;
}

/// Checks every RULE-ID citation in [docs] (repo-relative POSIX paths)
/// against the registry.
RuleIdResult checkRuleIds(String repoRoot, List<String> docs) {
  final en = _registryRows(repoRoot, enRegistry);
  final vi = _registryRows(repoRoot, viRegistry);
  if (en.isEmpty && vi.isEmpty) {
    return RuleIdResult(
      registryFound: false,
      registered: const {},
      citations: 0,
      problems: const [],
    );
  }

  final problems = <String>[];
  for (final (rel, rows) in [(enRegistry, en), (viRegistry, vi)]) {
    for (final entry in rows.entries) {
      if (entry.value.length > 1) {
        problems.add(
          '$rel:${entry.value[1]}  ${entry.key} is defined more than once '
          '(lines ${entry.value.join(', ')})',
        );
      }
    }
  }
  for (final id in _sorted(en.keys.toSet().difference(vi.keys.toSet()))) {
    problems.add(
      '$enRegistry:${en[id]!.first}  $id has no row in $viRegistry',
    );
  }
  for (final id in _sorted(vi.keys.toSet().difference(en.keys.toSet()))) {
    problems.add(
      '$viRegistry:${vi[id]!.first}  $id has no row in $enRegistry '
      '(the English registry is the source of truth)',
    );
  }

  final registered = en.keys.toSet();
  var citations = 0;
  for (final rel in docs) {
    final lines = File(p.join(repoRoot, rel)).readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      for (final m in _citation.allMatches(lines[i])) {
        citations++;
        final id = m.group(0)!;
        if (registered.contains(id)) continue;
        // A vi-only registry row is already reported above.
        if (rel == viRegistry && vi.containsKey(id)) continue;
        problems.add('$rel:${i + 1}  $id is not in the registry');
      }
    }
  }

  return RuleIdResult(
    registryFound: true,
    registered: registered,
    citations: citations,
    problems: problems,
  );
}

List<String> _sorted(Set<String> ids) => ids.toList()..sort();
