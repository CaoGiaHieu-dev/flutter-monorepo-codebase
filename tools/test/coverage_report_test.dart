import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../coverage_report/report.dart';
import 'support/tool_harness.dart';

/// `tools/coverage_report/report.dart` — the per-package coverage table CI Gate 3
/// writes to the job summary.
void main() {
  group('parseLcov', () {
    test('counts DA lines per file and drops generated files', () {
      final files = parseLcov('''
SF:lib/src/a.dart
DA:1,1
DA:2,0
DA:3,4
LF:3
LH:2
end_of_record
SF:lib/src/a.freezed.dart
DA:1,0
end_of_record
SF:lib/src/gen/language/app_localizations.dart
DA:1,0
end_of_record
SF:/abs/pkg/lib/di/module.module.dart
DA:1,1
end_of_record
SF:lib/src/b.dart
DA:7,0
DA:7,2
end_of_record
''');
      expect(
        [for (final f in files) f.path],
        [
          'lib/src/a.dart',
          'lib/src/b.dart',
        ],
      );
      expect([for (final f in files) (f.found, f.hit)], [(3, 2), (1, 1)]);
    });

    test('recognises every generated shape, and only those', () {
      for (final path in [
        'lib/a.g.dart',
        'lib/a.freezed.dart',
        'lib/di/injection.config.dart',
        'lib/di/module.module.dart',
        'lib/a.gr.dart',
        'test/a.mocks.dart',
        r'C:\pkg\lib\src\gen\assets.gen.dart',
      ]) {
        expect(isGeneratedFile(path), isTrue, reason: path);
      }
      for (final path in ['lib/generator.dart', 'lib/src/gene/x.dart']) {
        expect(isGeneratedFile(path), isFalse, reason: path);
      }
    });
  });

  test('renderTable: one row per package, sorted, and a total', () {
    final table = renderTable([
      PackageCoverage('feature_b', 'modules/b/feature', [
        FileCoverage('x', 10, 5),
      ]),
      PackageCoverage('core_a', 'platform/a', [
        FileCoverage('y', 3, 3),
        FileCoverage('z', 1, 0),
      ]),
      PackageCoverage('core_empty', 'platform/empty', const []),
    ]);
    final rows = table.split('\n').where((l) => l.startsWith('| ')).toList();
    expect(rows, [
      '| Package | Path | Files | Lines | Covered | % |',
      '| `feature_b` | `modules/b/feature` | 1 | 10 | 5 | 50.0 |',
      '| `core_a` | `platform/a` | 2 | 4 | 3 | 75.0 |',
      '| `core_empty` | `platform/empty` | 0 | 0 | 0 | — |',
      '| **Total** | 3 package(s) | 3 | 14 | 8 | **57.1** |',
    ]);
  });

  // Every run but the one asserting the summary passes --no-summary: under
  // GitHub Actions `GITHUB_STEP_SUMMARY` is set for this test process too,
  // and the fixtures' tables would land in the real job summary.
  group('CLI', () {
    late CompiledTool tool;

    setUpAll(() async {
      tool = await CompiledTool.compile('tools/coverage_report/report.dart');
    });
    tearDownAll(() => tool.dispose());

    const lcovHalf = 'SF:lib/a.dart\nDA:1,1\nDA:2,0\nend_of_record\n';
    const lcovFull = 'SF:lib/a.dart\nDA:1,1\nend_of_record\n';

    TempWorkspace workspace() => TempWorkspace.create({
      'platform/a/pubspec.yaml': 'name: core_a\n',
      'platform/a/coverage/lcov.info': lcovHalf,
      'modules/b/feature/pubspec.yaml': 'name: feature_b\n',
      'modules/b/feature/coverage/lcov.info': lcovFull,
      // Never read: build output.
      'platform/a/build/coverage/lcov.info': lcovHalf,
    });

    test('discovers every package and writes the job summary', () async {
      final ws = workspace();
      final summary = p.join(ws.root, 'summary.md');
      final result = await Process.run(
        dartExecutable,
        [tool.dill],
        workingDirectory: ws.root,
        environment: {'GITHUB_STEP_SUMMARY': summary},
      );
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(
        '${result.stdout}',
        contains('| `feature_b` | `modules/b/feature` | 1 | 1 | 1 | 100.0 |'),
      );
      expect(
        '${result.stdout}',
        contains('| `core_a` | `platform/a` | 1 | 2 | 1 | 50.0 |'),
      );
      expect('${result.stdout}', contains('| **Total** | 2 package(s) |'));
      expect(File(summary).readAsStringSync(), contains('### Line coverage'));
    });

    test('--min fails on the total, --min-package on any package', () async {
      final ws = workspace();
      expect(
        await tool.run([
          '--min',
          '66',
          '--no-summary',
        ], workingDirectory: ws.root),
        exitsWith(0),
      );
      final total = await tool.run([
        '--min',
        '67',
        '--no-summary',
      ], workingDirectory: ws.root);
      expect(total, exitsWith(1));
      expect(total.output, contains('Total line coverage 66.7% is below'));

      final perPackage = await tool.run(
        ['--min-package', '60', '--no-summary'],
        workingDirectory: ws.root,
      );
      expect(perPackage, exitsWith(1));
      expect(perPackage.output, contains('core_a (platform/a): 50.0%'));
      expect(perPackage.output, isNot(contains('feature_b (')));
    });

    test('an explicit file is read on its own', () async {
      final ws = workspace();
      final run = await tool.run(
        ['modules/b/feature/coverage/lcov.info', '--no-summary'],
        workingDirectory: ws.root,
      );
      expect(run, exitsWith(0));
      expect(run.output, contains('| **Total** | 1 package(s) |'));
    });

    test('no lcov.info at all exits 1', () async {
      final ws = TempWorkspace.create({'pubspec.yaml': 'name: ws\n'});
      final run = await tool.run(const [], workingDirectory: ws.root);
      expect(run, exitsWith(1));
      expect(run.output, contains('flutter test --coverage'));
    });

    test('bad arguments exit 64', () async {
      final ws = workspace();
      for (final args in [
        ['--min'],
        ['--min', 'lots'],
        ['--min-package', '101'],
        ['--fail-under', '5'],
        ['missing/lcov.info'],
      ]) {
        expect(
          await tool.run(args, workingDirectory: ws.root),
          exitsWith(64),
          reason: '$args',
        );
      }
    });
  });
}
