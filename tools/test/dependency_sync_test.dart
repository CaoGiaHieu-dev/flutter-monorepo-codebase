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
}
