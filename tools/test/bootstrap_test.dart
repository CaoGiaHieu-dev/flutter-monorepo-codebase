import 'package:test/test.dart';

import 'support/tool_harness.dart';

/// `tools/composer/bootstrap.dart` — makes a partial checkout (a module
/// submodule not initialised) resolvable before `pub get` can run.
void main() {
  late CompiledTool tool;

  setUpAll(() async {
    tool = await CompiledTool.compile('tools/composer/bootstrap.dart');
  });
  tearDownAll(() => tool.dispose());

  const rootPubspec =
      'name: ws\n'
      'workspace:\n'
      '  # composer:managed:workspace — generated from app_manifest.yaml\n'
      '  - apps/demo\n'
      '  - modules/gone/feature\n'
      '  - platform/common\n'
      '  # composer:end:workspace\n';

  const appPubspec =
      'name: demo_app\n'
      'dependencies:\n'
      '  # composer:managed:deps — generated from app_manifest.yaml\n'
      '  core_common:\n'
      '    path: ../../platform/common\n'
      '  feature_gone:\n'
      '    path: ../../modules/gone/feature\n'
      '  # composer:end:deps\n';

  TempWorkspace partialCheckout() {
    final ws = TempWorkspace.create({
      'pubspec.yaml': rootPubspec,
      'apps/demo/pubspec.yaml': appPubspec,
      'platform/common/pubspec.yaml': 'name: core_common\n',
    });
    // The uninitialised submodule: its directory exists, empty.
    ws.mkdir('modules/gone/feature');
    return ws;
  }

  test('--dry-run reports the missing member and writes nothing', () async {
    final ws = partialCheckout();
    final run = await tool.run(const ['--dry-run'], workingDirectory: ws.root);

    expect(run, exitsWith(0));
    expect(
      run.output,
      contains('would prune 1 workspace member(s) with no pubspec.yaml'),
    );
    expect(run.output, contains('- modules/gone/feature'));
    expect(
      run.output,
      contains('apps/demo/pubspec.yaml — would prune 1 path dependency(ies)'),
    );
    expect(run.output, contains('- feature_gone'));
    expect(run.output, contains('Dry run: nothing was written.'));
    expect(ws.read('pubspec.yaml'), rootPubspec);
    expect(ws.read('apps/demo/pubspec.yaml'), appPubspec);
  });

  test('without --dry-run the managed regions are pruned', () async {
    final ws = partialCheckout();
    expect(await tool.run(const [], workingDirectory: ws.root), exitsWith(0));

    final root = ws.read('pubspec.yaml');
    expect(root, isNot(contains('modules/gone/feature')));
    expect(root, contains('  - platform/common\n'));
    final app = ws.read('apps/demo/pubspec.yaml');
    expect(app, isNot(contains('feature_gone')));
    expect(app, contains('  core_common:\n    path: ../../platform/common\n'));
  });

  test('a complete checkout has nothing to prune', () async {
    final ws = partialCheckout();
    ws.write({'modules/gone/feature/pubspec.yaml': 'name: feature_gone\n'});
    final run = await tool.run(const ['--dry-run'], workingDirectory: ws.root);
    expect(run, exitsWith(0));
    expect(run.output, contains('nothing to prune'));
  });

  test('outside a composer workspace it refuses', () async {
    final ws = TempWorkspace.create({'pubspec.yaml': 'name: ws\n'});
    final run = await tool.run(const ['--dry-run'], workingDirectory: ws.root);
    expect(run, exitsWith(1));
    expect(run.output, contains('No `composer:managed:workspace` region'));
  });
}
