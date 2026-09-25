import 'package:test/test.dart';

import '../module_generator/src/common_helpers.dart';
import '../module_generator/src/module_type.dart';
import 'support/tool_harness.dart';

/// `tools/module_generator/generate.dart` — argument handling that must
/// stop a run before anything is written, and the manifest edit `--apps`
/// narrows.
///
/// A full generation (pub get, build_runner) is the `generator-smoke` CI
/// job's business; here the generator runs only as far as its validation.
/// It locates the repository from its own script location, so the snapshot
/// is copied into each temp workspace.
void main() {
  late CompiledTool tool;

  setUpAll(() async {
    tool = await CompiledTool.compile('tools/module_generator/generate.dart');
  });
  tearDownAll(() => tool.dispose());

  const mobile = '''
app:
  id: mobile
  kind: flutter

di_groups:
  - name: core
    phase: before
    packages:
      - core_common

modules:
  - { id: auth, layers: [domain, data, feature] }
''';
  const admin = '''
app:
  id: admin

di_groups:
  - name: core
    phase: before
    packages: [core_common]

modules:
  - { id: auth, layers: [feature] }
''';

  TempWorkspace workspace() => TempWorkspace.create({
    'pubspec.yaml': 'name: ws\nworkspace:\n  - apps/mobile\n',
    'apps/mobile/app_manifest.yaml': mobile,
    'apps/mobile/pubspec.yaml': 'name: mobile\n',
    'apps/admin/app_manifest.yaml': admin,
    'apps/admin/pubspec.yaml': 'name: admin\n',
  });

  Future<ToolRun> generate(TempWorkspace ws, List<String> args) => tool.run(
    args,
    workingDirectory: ws.root,
    scriptPath: 'tools/module_generator/generate.dill',
  );

  group('--apps is validated before anything is written', () {
    for (final (label, args, message) in [
      (
        'an unknown id',
        ['1', 'chat', '', '2', '2', '--apps', 'mobile,tablet'],
        'Unknown app id(s) in --apps: tablet',
      ),
      (
        'an unknown id, = form',
        ['1', 'chat', '', '2', '2', '--apps=tv'],
        'Known apps (app.id in apps/*/app_manifest.yaml): admin, mobile',
      ),
      ('no value', ['2', 'chat', '--apps'], '--apps needs a value.'),
      (
        'an empty list',
        ['2', 'chat', '--apps', ','],
        '--apps needs at least one app id',
      ),
      (
        'given twice',
        ['2', 'chat', '--apps', 'mobile', '--apps=admin'],
        '--apps given more than once.',
      ),
    ]) {
      test('$label exits 64', () async {
        final ws = workspace();
        final run = await generate(ws, args);
        expect(run, exitsWith(64));
        expect(run.output, contains(message));
        expect(ws.exists('modules/chat'), isFalse);
        expect(ws.read('apps/mobile/app_manifest.yaml'), mobile);
        expect(ws.read('apps/admin/app_manifest.yaml'), admin);
      });
    }

    test('another unknown flag is still refused', () async {
      final ws = workspace();
      final run = await generate(ws, ['2', 'chat', '--app', 'mobile']);
      expect(run, exitsWith(64));
      expect(run.output, contains('Unknown flag: --app'));
    });

    test('--help documents the flag', () async {
      final run = await generate(workspace(), ['--help']);
      expect(run, exitsWith(0));
      expect(run.output, contains('--apps <id,id>'));
    });
  });

  group('--group places a core/custom package under platform/<group>/', () {
    for (final (label, args, message) in [
      (
        'an unknown group',
        ['4', 'charts', '--group', 'widgets'],
        'Unknown --group "widgets". Platform groups: foundation, layers, '
            'infra, ui, state, shell.',
      ),
      ('no value', ['4', 'charts', '--group'], '--group needs a value.'),
      (
        'given twice',
        ['4', 'charts', '--group', 'ui', '--group=infra'],
        '--group given more than once.',
      ),
      (
        'a module layer',
        ['2', 'charts', '--group', 'ui'],
        '--group applies to types 4 (Core) and 5 (Custom) only',
      ),
    ]) {
      test('$label exits 64', () async {
        final ws = workspace();
        final run = await generate(ws, args);
        expect(run, exitsWith(64));
        expect(run.output, contains(message));
        expect(ws.exists('platform'), isFalse);
        expect(ws.exists('modules/charts'), isFalse);
      });
    }

    // The target directory is resolved before the toolchain check, so an
    // existing directory there shows exactly where the package would go.
    for (final (label, args, path) in [
      ('type 4 defaults to infra', ['4', 'charts'], 'platform/infra/charts'),
      (
        'type 4 with --group ui',
        ['4', 'charts', '--group', 'ui'],
        'platform/ui/charts',
      ),
      (
        'type 5 with --group=foundation',
        ['5', 'charts', 'acme', '--group=foundation'],
        'platform/foundation/charts',
      ),
    ]) {
      test('$label resolves to $path', () async {
        final ws = workspace()..mkdir(path);
        final run = await generate(ws, args);
        expect(run, exitsWith(1));
        expect(run.output, contains('Directory "$path" already exists'));
      });
    }

    test('--help documents the flag', () async {
      final run = await generate(workspace(), ['--help']);
      expect(run, exitsWith(0));
      expect(run.output, contains('--group <group>'));
    });
  });

  group('type 6 creates a module API package', () {
    for (final (label, args, message) in [
      (
        'a state-management argument',
        ['6', 'chat', '', '1'],
        '<SM> and <route> apply to type 1 (Feature) only.',
      ),
      (
        'a prefix',
        ['6', 'chat', 'acme'],
        '<prefix> applies to type 5 only',
      ),
      (
        'a platform group',
        ['6', 'chat', '--group', 'ui'],
        '--group applies to types 4 (Core) and 5 (Custom) only',
      ),
      ('an invalid name', ['6', 'Chat'], 'Module name "Chat" is invalid'),
    ]) {
      test('$label exits 64', () async {
        final ws = workspace();
        final run = await generate(ws, args);
        expect(run, exitsWith(64));
        expect(run.output, contains(message));
        expect(ws.exists('modules/chat'), isFalse);
        expect(ws.read('apps/mobile/app_manifest.yaml'), mobile);
      });
    }

    test('an existing <name>_api package name exits 64', () async {
      final ws = workspace()
        ..write({'modules/talk/api/pubspec.yaml': 'name: chat_api\n'});
      final run = await generate(ws, ['6', 'chat']);
      expect(run, exitsWith(64));
      expect(run.output, contains('Package "chat_api" already exists'));
    });

    test('resolves to modules/<name>/api', () async {
      final ws = workspace()..mkdir('modules/chat/api');
      final run = await generate(ws, ['6', 'chat']);
      expect(run, exitsWith(1));
      expect(
        run.output,
        contains('Directory "modules/chat/api" already exists'),
      );
    });

    test('--help lists the type', () async {
      final run = await generate(workspace(), ['--help']);
      expect(run, exitsWith(0));
      expect(run.output, contains('6 = API'));
    });

    test('the manifests list the api layer, first', () {
      final ws = workspace();
      CommonHelpers.registerInAppManifests(
        'auth_api',
        ModuleType.api,
        'auth',
        root: ws.root,
      );
      CommonHelpers.registerInAppManifests(
        'chat_api',
        ModuleType.api,
        'chat',
        apps: const ['mobile'],
        root: ws.root,
      );
      expect(
        ws.read('apps/mobile/app_manifest.yaml'),
        allOf(
          contains('  - { id: auth, layers: [api, domain, data, feature] }'),
          contains('  - { id: chat, layers: [api] }'),
        ),
      );
      expect(
        ws.read('apps/admin/app_manifest.yaml'),
        contains('  - { id: auth, layers: [api, feature] }'),
      );
    });
  });

  group('registerInAppManifests', () {
    test('without apps, composes into every manifest', () {
      final ws = workspace();
      CommonHelpers.registerInAppManifests(
        'feature_chat',
        ModuleType.feature,
        'chat',
        root: ws.root,
      );
      expect(
        ws.read('apps/mobile/app_manifest.yaml'),
        contains('  - { id: chat, layers: [feature] }'),
      );
      expect(
        ws.read('apps/admin/app_manifest.yaml'),
        contains('  - { id: chat, layers: [feature] }'),
      );
    });

    test('with apps, touches only the listed manifests', () {
      final ws = workspace();
      CommonHelpers.registerInAppManifests(
        'feature_chat',
        ModuleType.feature,
        'chat',
        apps: const ['mobile'],
        root: ws.root,
      );
      expect(
        ws.read('apps/mobile/app_manifest.yaml'),
        contains('  - { id: chat, layers: [feature] }'),
      );
      expect(ws.read('apps/admin/app_manifest.yaml'), admin);
    });

    test('a platform package joins the core group of the listed app only', () {
      final ws = workspace();
      CommonHelpers.registerInAppManifests(
        'core_analytics',
        ModuleType.core,
        'analytics',
        apps: const ['admin'],
        root: ws.root,
      );
      expect(
        ws.read('apps/admin/app_manifest.yaml'),
        contains('packages: [core_common, core_analytics]'),
      );
      expect(ws.read('apps/mobile/app_manifest.yaml'), mobile);
    });
  });
}
