import 'package:test/test.dart';

import 'support/tool_harness.dart';

/// `tools/dependency_sync.dart --check` — CI Gate 4.
///
/// Only `--check` is exercised: without it the tool rewrites pubspecs and
/// then runs `dart pub get`, which would need the network and a resolvable
/// workspace.
void main() {
  late CompiledTool tool;

  setUpAll(() async {
    tool = await CompiledTool.compile('tools/dependency_sync.dart');
  });
  tearDownAll(() => tool.dispose());

  Future<ToolRun> check({
    required String catalog,
    required String memberPubspec,
  }) {
    final ws = TempWorkspace.create({
      'pubspec_dependencies.yaml': catalog,
      'pubspec.yaml': 'name: ws\nworkspace:\n  - platform/foo\n',
      'platform/foo/pubspec.yaml': memberPubspec,
    });
    return tool.run(const ['--check'], workingDirectory: ws.root);
  }

  const catalog =
      'dependencies:\n'
      '  path: "^1.9.1"\n'
      'dev_dependencies:\n'
      '  test: "^1.31.1"\n';

  test('a workspace in step with the catalog passes', () async {
    final run = await check(
      catalog: catalog,
      memberPubspec:
          'name: core_foo\n'
          'dependencies:\n'
          '  path: "^1.9.1"\n'
          'dev_dependencies:\n'
          '  test: ^1.31.1\n',
    );
    expect(run, exitsWith(0));
    expect(run.output, contains('perfect sync'));
  });

  test('a version that differs from the catalog exits 1', () async {
    final run = await check(
      catalog: catalog,
      memberPubspec:
          'name: core_foo\n'
          'dependencies:\n'
          '  path: ^1.8.0\n',
    );
    expect(run, exitsWith(1));
    expect(
      run.output,
      contains(
        'Mismatch: [platform/foo/pubspec.yaml] uses path: "^1.8.0" instead '
        'of "^1.9.1"',
      ),
    );
  });

  test('a malformed catalog is refused', () async {
    final run = await check(
      // An unquoted number is a YAML double, not a version constraint.
      catalog: 'dependencies:\n  path: 1.9\n',
      memberPubspec: 'name: core_foo\n',
    );
    expect(run, exitsWith(1));
    expect(
      run.output,
      contains('pubspec_dependencies.yaml: dependencies.path'),
    );
    expect(run.output, contains('quote it'));
  });

  test('a catalog that is not valid YAML is refused', () async {
    final run = await check(
      catalog: 'dependencies:\n  path: "^1.9.1"\n  path: "^1.9.0"\n',
      memberPubspec: 'name: core_foo\n',
    );
    expect(run, exitsWith(1));
    expect(run.output, contains('pubspec_dependencies.yaml'));
  });

  group('RULE-74: a hosted dependency the catalog does not pin', () {
    test('a dependency missing from the catalog exits 1 naming it', () async {
      final run = await check(
        catalog: catalog,
        memberPubspec:
            'name: core_foo\n'
            'dependencies:\n'
            '  path: ^1.9.1\n'
            '  rogue_pkg: ^2.0.0\n',
      );
      expect(run, exitsWith(1));
      expect(
        run.output,
        contains(
          'Not in the catalog: [platform/foo/pubspec.yaml] '
          'dependencies.rogue_pkg',
        ),
      );
      expect(run.output, contains('RULE-74'));
    });

    test('a dev_dependency missing from the catalog exits 1', () async {
      final run = await check(
        catalog: catalog,
        memberPubspec:
            'name: core_foo\n'
            'dev_dependencies:\n'
            '  rogue_tool: ^1.0.0\n',
      );
      expect(run, exitsWith(1));
      expect(
        run.output,
        contains('[platform/foo/pubspec.yaml] dev_dependencies.rogue_tool'),
      );
    });

    test('a hosted map source and a bare `any` are caught too', () async {
      final run = await check(
        catalog: catalog,
        memberPubspec:
            'name: core_foo\n'
            'dependencies:\n'
            '  a_pkg:\n'
            '    hosted: https://pub.example.com\n'
            '    version: ^1.0.0\n'
            '  b_pkg: any\n',
      );
      expect(run, exitsWith(1));
      expect(run.output, contains('dependencies.a_pkg'));
      expect(run.output, contains('dependencies.b_pkg'));
    });

    test('sdk, path and git sources are not the catalog\'s business', () async {
      final run = await check(
        catalog: catalog,
        memberPubspec:
            'name: core_foo\n'
            'dependencies:\n'
            '  flutter:\n'
            '    sdk: flutter\n'
            '  local_pkg:\n'
            '    path: ../local\n'
            '  git_pkg:\n'
            '    git:\n'
            '      url: https://example.com/git_pkg.git\n',
      );
      expect(run, exitsWith(0));
    });
  });
}
