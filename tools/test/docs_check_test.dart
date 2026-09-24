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
    expect(run.output, isNot(contains('INFO:')));
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
}
