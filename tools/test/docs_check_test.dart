import 'dart:io';

import 'package:test/test.dart';

import 'support/tool_harness.dart';

/// `tools/docs_check/check.dart` — CI Gate 5.
///
/// The tool finds the repository from its **own** location (the nearest
/// ancestor holding `pubspec.yaml` + `tools/`), not from the working
/// directory, so the snapshot is copied into each temp workspace at
/// `tools/docs_check/check.dill`.
void main() {
  late CompiledTool tool;

  setUpAll(() async {
    tool = await CompiledTool.compile('tools/docs_check/check.dart');
  });
  tearDownAll(() => tool.dispose());

  Future<ToolRun> check(Map<String, String> files, {List<String>? args}) {
    final ws = TempWorkspace.create({
      'pubspec.yaml': 'name: ws\n',
      'platform/common/lib/common.dart': '',
      ...files,
    });
    return tool.run(
      args ?? const [],
      workingDirectory: ws.root,
      scriptPath: 'tools/docs_check/check.dill',
    );
  }

  test('a reference that exists passes', () async {
    final run = await check({
      'README.md':
          'See `platform/common/lib/common.dart` and `platform/common/`.\n',
    });
    expect(run, exitsWith(0));
    expect(run.output, contains('OK — every documented path exists on disk.'));
    expect(run.output, contains('references: 2'));
  });

  test('a dead reference exits 1 and names the line', () async {
    final run = await check({
      'docs/guide.md': 'intro\nRun `platform/missing/tool.dart` first.\n',
    });
    expect(run, exitsWith(1));
    expect(run.output, contains('1 dead reference(s)'));
    expect(
      run.output,
      contains('docs/guide.md:2  [path] platform/missing/tool.dart'),
    );
  });

  test('a dead relative link exits 1', () async {
    final run = await check({
      'docs/guide.md': 'See [the tour](../platform/nope.md).\n',
    });
    expect(run, exitsWith(1));
    expect(
      run.output,
      contains('[link] ../platform/nope.md -> platform/nope.md'),
    );
  });

  test('only the part before a <placeholder> must exist', () async {
    final run = await check({
      'README.md':
          'Barrels: `platform/common/lib/<module>/<layer>.dart`.\n'
          '```\n'
          'platform/ignored/inside/a/fence.dart\n'
          '```\n',
    });
    expect(run, exitsWith(0));
  });

  test('a placeholder whose prefix is missing still fails', () async {
    final run = await check({
      'README.md': 'Barrels: `platform/nowhere/<module>/lib`.\n',
    });
    expect(run, exitsWith(1));
    expect(run.output, contains('[pattern] platform/nowhere/<module>/lib'));
  });

  test('an allowlisted path passes', () async {
    final run = await check({
      'tools/docs_check/allowlist.txt':
          'apps/mobile/env.prod   # secret, never committed\n',
      'README.md': 'Create `apps/mobile/env.prod` yourself.\n',
    });
    expect(run, exitsWith(0));
  });

  test('a reference into a removed sample bundle is INFO, exit 0', () async {
    final run = await check({
      'tools/sample_manifest.yaml':
          'packages:\n'
          '  feature_gone: { kind: sample, path: modules/gone/feature }\n'
          'bundles:\n'
          '  gone:\n'
          '    packages: [feature_gone]\n',
      'README.md':
          'The sample lives in `modules/gone/feature/lib/gone.dart`.\n',
    });
    expect(run, exitsWith(0));
    expect(
      run.output,
      contains(
        'INFO: 1 reference(s) in 1 document(s) point to removed sample '
        'bundle "gone"',
      ),
    );
    expect(run.output, contains('outside the removed samples exists'));
  });

  test('a bundle whose kept API package survives is still removed', () async {
    final run = await check({
      'tools/sample_manifest.yaml':
          'packages:\n'
          '  feature_gone: { kind: sample, path: modules/gone/feature }\n'
          '  domain_gone: { kind: sample, path: modules/gone/domain }\n'
          '  gone_api: { kind: sample, path: modules/gone/api }\n'
          'bundles:\n'
          '  gone:\n'
          '    packages: [feature_gone, domain_gone, gone_api]\n',
      // Kept by remove_sample: another package still imports it.
      'modules/gone/api/pubspec.yaml': 'name: gone_api\n',
      'README.md':
          'Implemented in `modules/gone/feature/lib/gone.dart`, declared in '
          '`modules/gone/api/pubspec.yaml`; the slice was '
          '`modules/gone/{feature,domain}`.\n',
    });
    expect(run, exitsWith(0));
    expect(run.output, contains('removed sample bundle "gone"'));
  });

  test('a bundle still on disk is not treated as removed', () async {
    final run = await check({
      'tools/sample_manifest.yaml':
          'packages:\n'
          '  feature_kept: { kind: sample, path: modules/kept/feature }\n'
          'bundles:\n'
          '  kept:\n'
          '    packages: [feature_kept]\n',
      'modules/kept/feature/pubspec.yaml': 'name: feature_kept\n',
      'README.md': 'See `modules/kept/feature/lib/missing.dart`.\n',
    });
    expect(run, exitsWith(1));
    expect(run.output, isNot(contains('removed sample bundle')));
  });

  test('the root comes from the script location, not the cwd', () async {
    final ws = TempWorkspace.create({
      'pubspec.yaml': 'name: ws\n',
      'docs/guide.md': 'Run `platform/missing/tool.dart` first.\n',
    });
    // Started from docs/: a cwd-rooted check would find no dead reference
    // outside it — and no `platform/` to resolve against.
    final run = await tool.run(
      const [],
      workingDirectory: '${ws.root}/docs',
      scriptPath: '../tools/docs_check/check.dill',
    );
    expect(run, exitsWith(1));
    expect(run.output, contains('docs/guide.md:1  [path]'));
  });

  test('an unknown argument exits 64', () async {
    final run = await check(const {'README.md': ''}, args: const ['--fix']);
    expect(run, exitsWith(64));
  });

  group('en <-> vi parity', () {
    const en =
        '# Guide\n\n## Setup\n\n```bash\nflutter pub get\n```\n\n'
        '| a | b |\n|---|---|\n| 1 | 2 |\n\n> | quoted | row |\n';
    const vi =
        '# Hướng dẫn\n\n## Cài đặt\n\n```bash\nflutter pub get\n```\n\n'
        '| a | b |\n|---|---|\n| 1 | 2 |\n\n> | quoted | row |\n';

    test('translated pairs with the same shape pass', () async {
      final run = await check({
        'docs/en/guide.md': en,
        'docs/vi/guide.md': vi,
        'README.md': en,
        'README.vi.md': vi,
        // No counterpart: not compared.
        'docs/en/only_english.md': '## lonely\n',
      });
      expect(run, exitsWith(0));
      expect(run.output, contains('pairs     : 2'));
      expect(run.output, contains('every translated document has the shape'));
    });

    test(
      'a missing section, block and row fail with en vs vi counts',
      () async {
        final run = await check({
          'docs/en/guide.md': '$en\n### Extra\n\n```\nmore\n```\n| 3 | 4 |\n',
          'docs/vi/guide.md': vi,
        });
        expect(run, exitsWith(1));
        expect(run.output, contains('3 parity mismatch(es)'));
        expect(
          run.output,
          contains('docs/en/guide.md  h3: en 1 vs vi 0  (docs/vi/guide.md)'),
        );
        expect(
          run.output,
          contains('docs/en/guide.md  code-blocks: en 2 vs vi 1'),
        );
        expect(
          run.output,
          contains('docs/en/guide.md  table-rows: en 5 vs vi 4'),
        );
      },
    );

    test('a README.vi.md beside its README.md is a pair', () async {
      final run = await check({
        'tools/x/README.md': '## One\n## Two\n',
        'tools/x/README.vi.md': '## Một\n',
      });
      expect(run, exitsWith(1));
      expect(run.output, contains('tools/x/README.md  h2: en 2 vs vi 1'));
    });

    test('a heading or table inside a fence is code, not structure', () async {
      final run = await check({
        'docs/en/guide.md':
            '````md\n## not a heading\n| x |\n```\n````\n'
            '> ```bash\n> | quoted fence |\n> ```\n',
        'docs/vi/guide.md': '````md\nkhác\n````\n> ```bash\n> khác\n> ```\n',
      });
      expect(run, exitsWith(0));
    });

    test('an allowlisted difference passes; a stale entry warns', () async {
      final run = await check({
        'docs/en/guide.md': '## One\n## Two\n',
        'docs/vi/guide.md': '## Một\n',
        'tools/docs_check/parity_allowlist.txt':
            'docs/en/guide.md h2  # vi merges the two sections\n'
            'docs/en/gone.md *  # was different once\n',
      });
      expect(run, exitsWith(0));
      expect(
        run.output,
        contains(
          'WARN: parity_allowlist.txt entry '
          '"docs/en/gone.md *" matches no difference',
        ),
      );
    });

    test('an allowlist entry without a reason is refused', () async {
      final run = await check({
        'docs/en/guide.md': '## One\n## Two\n',
        'docs/vi/guide.md': '## Một\n',
        'tools/docs_check/parity_allowlist.txt':
            'docs/en/guide.md h2\ndocs/en/guide.md words  # bad metric\n',
      });
      expect(run, exitsWith(1));
      expect(
        run.output,
        contains('line 1: "docs/en/guide.md h2" has no reason'),
      );
      expect(
        run.output,
        contains('line 2: expected "<english file> <metric>"'),
      );
      expect(run.output, contains('1 parity mismatch(es)'));
    });
  });

  group('RULE-ID citations', () {
    String registry(List<String> ids) =>
        '# Rules\n\n| ID | Rule |\n|---|---|\n'
        '${ids.map((id) => '| $id | text |\n').join()}';

    test('no registry yet: skipped with INFO, citations ignored', () async {
      final run = await check({
        'docs/en/guide.md': 'See RULE-42.\n',
      });
      expect(run, exitsWith(0));
      expect(run.output, contains('citation check skipped'));
    });

    test('citations of registered IDs pass, in any Markdown file', () async {
      final run = await check({
        'docs/en/reference/01_rules.md': registry(['RULE-01', 'RULE-02']),
        'docs/vi/reference/01_rules.md': registry(['RULE-01', 'RULE-02']),
        'docs/en/guide.md': 'Layering (RULE-01, RULE-02). Cite as RULE-NN.\n',
        '.claude/skills/x/SKILL.md': 'Follow RULE-02.\n',
        'tools/code_review/review_prompt.md': 'Tag findings RULE-01.\n',
      });
      expect(run, exitsWith(0));
      expect(run.output, contains('registry  : 2 rule(s)'));
      expect(run.output, contains('every cited RULE-ID is defined'));
    });

    test('a dangling citation exits 1 with file:line', () async {
      final run = await check({
        'docs/en/reference/01_rules.md': registry(['RULE-01']),
        'docs/vi/reference/01_rules.md': registry(['RULE-01']),
        'docs/en/guide.md': 'intro\nSee RULE-09 and RULE-1.\n',
        '.claude/skills/x/SKILL.md': 'Follow RULE-77.\n',
      });
      expect(run, exitsWith(1));
      expect(run.output, contains('3 RULE-ID problem(s)'));
      expect(
        run.output,
        contains('docs/en/guide.md:2  RULE-09 is not in the registry'),
      );
      expect(
        run.output,
        contains('docs/en/guide.md:2  RULE-1 is not in the registry'),
      );
      expect(run.output, contains('.claude/skills/x/SKILL.md:1  RULE-77'));
    });

    test('en and vi registries defining different IDs fail', () async {
      final run = await check({
        'docs/en/reference/01_rules.md': registry(['RULE-01', 'RULE-02']),
        // Same shape, so parity passes: only the ID sets differ.
        'docs/vi/reference/01_rules.md': registry(['RULE-01', 'RULE-03']),
      });
      expect(run, exitsWith(1));
      expect(
        run.output,
        contains(
          'docs/en/reference/01_rules.md:6  RULE-02 has no row in '
          'docs/vi/reference/01_rules.md',
        ),
      );
      expect(
        run.output,
        contains(
          'docs/vi/reference/01_rules.md:6  RULE-03 has no row in '
          'docs/en/reference/01_rules.md',
        ),
      );
      expect(run.output, contains('every translated document has the shape'));
    });

    test('an ID defined twice fails', () async {
      final run = await check({
        'docs/en/reference/01_rules.md': registry(['RULE-01', 'RULE-01']),
        'docs/vi/reference/01_rules.md': registry(['RULE-01', 'RULE-01']),
      });
      expect(run, exitsWith(1));
      expect(
        run.output,
        contains(
          'docs/en/reference/01_rules.md:6  RULE-01 is defined more than '
          'once (lines 5, 6)',
        ),
      );
    });
  });

  group('stale translations', () {
    /// A git repository holding [files], committed once.
    TempWorkspace repo(Map<String, String> files) {
      final ws = TempWorkspace.create({'pubspec.yaml': 'name: ws\n', ...files});
      git(ws, ['init', '-q']);
      commitAll(ws, 'initial');
      return ws;
    }

    Future<ToolRun> run(TempWorkspace ws, [List<String> args = const []]) =>
        tool.run(
          args,
          workingDirectory: ws.root,
          scriptPath: 'tools/docs_check/check.dill',
        );

    test('no stamp anywhere: nothing is printed', () async {
      final ws = repo({
        'docs/en/a.md': '# A\n',
        'docs/vi/a.md': '# A vi\n',
      });
      final result = await run(ws);
      expect(result, exitsWith(0));
      expect(result.output, isNot(contains('Stale translations')));
    });

    test('--stamp-translations stamps the named file only', () async {
      final ws = repo({
        'docs/en/a.md': '# A\n',
        'docs/vi/a.md': '# A vi\n\nbody\n',
        'docs/en/b.md': '# B\n',
        'docs/vi/b.md': '# B vi\n',
      });
      final sha = git(ws, ['log', '-1', '--format=%h', '--', 'docs/en/a.md']);
      final result = await run(ws, ['--stamp-translations', 'docs/vi/a.md']);
      expect(result, exitsWith(0));
      expect(result.output, contains('1 written'));
      expect(
        ws.read('docs/vi/a.md'),
        '<!-- translated-from: docs/en/a.md@$sha -->\n# A vi\n\nbody\n',
      );
      expect(ws.read('docs/vi/b.md'), '# B vi\n');
    });

    test(
      'an English commit after the stamp is reported, never failed',
      () async {
        final ws = repo({
          'docs/en/a.md': '# A\n',
          'docs/vi/a.md': '# A vi\n',
          'docs/en/b.md': '# B\n',
          'docs/vi/b.md': '# B vi\n',
        });
        // Adopting stamps: every file at once.
        final stamped = await run(ws, ['--stamp-translations']);
        expect(stamped.output, contains('2 written'));
        commitAll(ws, 'stamp translations');

        ws.write({'docs/en/a.md': '# A\n\nNew paragraph.\n'});
        commitAll(ws, 'expand A');
        final latest = git(ws, ['log', '-1', '--format=%h']);

        final summary = await run(ws);
        expect(summary, exitsWith(0));
        expect(
          summary.output,
          contains(
            'INFO: 1 of 2 stamped translation(s) are behind their English '
            'source.',
          ),
        );
        expect(summary.output, contains('(--stale-translations lists them)'));
        expect(summary.output, isNot(contains('docs/vi/a.md  <-')));

        final detailed = await run(ws, ['--stale-translations']);
        expect(detailed, exitsWith(0));
        expect(
          detailed.output,
          contains('docs/vi/a.md  <- docs/en/a.md: 1 commit(s) since'),
        );
        expect(detailed.output, contains('(now $latest)'));
        expect(detailed.output, isNot(contains('docs/vi/b.md  <-')));

        // Re-syncing and re-stamping clears it; the old stamp is replaced.
        final restamp = await run(ws, ['--stamp-translations', 'docs/vi/a.md']);
        expect(restamp.output, contains('1 written'));
        expect(
          ws.read('docs/vi/a.md'),
          '<!-- translated-from: docs/en/a.md@$latest -->\n# A vi\n',
        );
        final after = await run(ws);
        expect(after.output, contains('INFO: 0 of 2 stamped'));
      },
    );

    test(
      'a stamp naming an unknown commit or a missing file is listed',
      () async {
        final ws = repo({
          'docs/en/a.md': '# A\n',
          'docs/vi/a.md':
              '<!-- translated-from: docs/en/a.md@0000000 -->\n# A vi\n',
          'docs/vi/c.md':
              '<!-- translated-from: docs/en/gone.md@0000000 -->\n# C vi\n',
        });
        final result = await run(ws, ['--stale-translations']);
        expect(result, exitsWith(0));
        expect(
          result.output,
          contains('docs/vi/a.md  <- docs/en/a.md: commit 0000000 not in'),
        );
        expect(
          result.output,
          contains('docs/vi/c.md  <- docs/en/gone.md: English file not found'),
        );
      },
    );

    test('outside a git checkout stamps are not compared', () async {
      final result = await check({
        'docs/en/a.md': '# A\n',
        'docs/vi/a.md':
            '<!-- translated-from: docs/en/a.md@1234567 -->\n# A vi\n',
      });
      expect(result, exitsWith(0));
      expect(result.output, contains('no git history here'));
    });

    test('a path outside docs/vi, or one without the flag, exits 64', () async {
      final ws = repo({'docs/en/a.md': '# A\n', 'docs/vi/a.md': '# A vi\n'});
      expect(
        await run(ws, ['--stamp-translations', 'docs/en/a.md']),
        exitsWith(64),
      );
      expect(await run(ws, ['docs/vi/a.md']), exitsWith(64));
      expect(
        await run(ws, ['--stamp-translations', '--stale-translations']),
        exitsWith(64),
      );
    });
  });
}

/// Runs git in [ws] and returns its trimmed stdout; fails the test on error.
/// Identity and signing are set per call so no global config is needed.
String git(TempWorkspace ws, List<String> args) {
  final r = Process.runSync('git', [
    '-c',
    'user.name=docs_check test',
    '-c',
    'user.email=test@example.invalid',
    '-c',
    'commit.gpgsign=false',
    ...args,
  ], workingDirectory: ws.root);
  if (r.exitCode != 0) {
    throw StateError('git ${args.join(' ')} failed: ${r.stderr}');
  }
  return '${r.stdout}'.trim();
}

/// Commits everything but the tool snapshot the harness copies in.
void commitAll(TempWorkspace ws, String message) {
  git(ws, ['add', '-A', '--', '.', ':(exclude)tools/docs_check/check.dill']);
  git(ws, ['commit', '-q', '-m', message]);
}
