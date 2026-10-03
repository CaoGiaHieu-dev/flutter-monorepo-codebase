import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/tool_harness.dart';

/// `tools/sample_cleanup/remove_sample.dart` — the module API package case.
///
/// Module `a` ships `a_api`, `domain_a` and `feature_a`; module `b`'s feature
/// imports `a_api`. Removing `a` must keep `a_api` while `feature_b` depends
/// on it (the build would not compile otherwise), rewrite the manifest entry
/// to the API layer alone, and delete it on a later run once nothing does.
void main() {
  late CompiledTool tool;

  setUpAll(() async {
    tool = await CompiledTool.compile(
      'tools/sample_cleanup/remove_sample.dart',
    );
  });
  tearDownAll(() => tool.dispose());

  TempWorkspace workspace({required bool bImportsApi}) => TempWorkspace.create({
    'pubspec.yaml':
        'name: ws\n'
        'workspace:\n'
        '  # composer:managed:workspace — generated from app_manifest.yaml\n'
        '  - apps/demo\n'
        '  - modules/a/api\n'
        '  - modules/a/domain\n'
        '  - modules/a/feature\n'
        '  - modules/b/feature\n'
        '  # composer:end:workspace\n',
    'tools/sample_manifest.yaml':
        'packages:\n'
        '  a_api: { kind: sample, path: modules/a/api }\n'
        '  domain_a: { kind: sample, path: modules/a/domain }\n'
        '  feature_a: { kind: sample, path: modules/a/feature }\n'
        '  feature_b: { kind: sample, path: modules/b/feature }\n'
        'bundles:\n'
        '  a:\n'
        '    packages: [feature_a, domain_a, a_api]\n'
        '  b:\n'
        '    packages: [feature_b]\n',
    'apps/demo/app_manifest.yaml':
        'app:\n'
        '  id: demo\n'
        'modules:\n'
        '  - { id: a, layers: [api, domain, feature] }\n'
        '  - { id: b, layers: [feature] }\n',
    'apps/demo/pubspec.yaml':
        'name: demo_app\n'
        'dependencies:\n'
        '  # composer:managed:deps — generated from app_manifest.yaml\n'
        '  domain_a:\n'
        '    path: ../../modules/a/domain\n'
        '  feature_a:\n'
        '    path: ../../modules/a/feature\n'
        '  feature_b:\n'
        '    path: ../../modules/b/feature\n'
        '  # composer:end:deps\n',
    'apps/demo/lib/di/injection.dart':
        "import 'package:domain_a/di/module.module.dart';\n"
        "import 'package:feature_a/di/module.module.dart';\n"
        "import 'package:feature_b/di/module.module.dart';\n",
    'modules/a/api/pubspec.yaml': 'name: a_api\n',
    'modules/a/domain/pubspec.yaml': 'name: domain_a\n',
    'modules/a/feature/pubspec.yaml':
        'name: feature_a\n'
        'dependencies:\n'
        '  a_api:\n'
        '    path: ../api\n',
    'modules/b/feature/pubspec.yaml': bImportsApi
        ? 'name: feature_b\n'
              'dependencies:\n'
              '  a_api:\n'
              '    path: ../../a/api\n'
        : 'name: feature_b\n',
  });

  Future<ToolRun> run(TempWorkspace ws, List<String> args) =>
      tool.run(args, workingDirectory: ws.root);

  bool exists(TempWorkspace ws, String path) =>
      Directory(p.join(ws.root, path)).existsSync();

  test('the dry run names the kept API package and writes nothing', () async {
    final ws = workspace(bImportsApi: true);
    final dry = await run(ws, ['a']);
    expect(dry, exitsWith(0));
    expect(dry.output, contains('k modules/a/api'));
    expect(dry.output, contains('still a dependency of feature_b'));
    expect(dry.output, contains('+ - { id: a, layers: [api] }'));
    expect(exists(ws, 'modules/a/feature'), isTrue);
  });

  test('an imported API package is kept, the rest removed', () async {
    final ws = workspace(bImportsApi: true);
    final apply = await run(ws, ['a', '--apply']);
    expect(apply, exitsWith(0));
    expect(apply.output, contains('imported by: feature_b'));

    expect(exists(ws, 'modules/a/api'), isTrue);
    expect(exists(ws, 'modules/a/domain'), isFalse);
    expect(exists(ws, 'modules/a/feature'), isFalse);

    final manifest = ws.read('apps/demo/app_manifest.yaml');
    expect(manifest, contains('  - { id: a, layers: [api] }\n'));
    expect(manifest, contains('  - { id: b, layers: [feature] }\n'));
    final root = ws.read('pubspec.yaml');
    expect(root, contains('  - modules/a/api\n'));
    expect(root, isNot(contains('modules/a/feature')));
    expect(ws.read('apps/demo/pubspec.yaml'), isNot(contains('feature_a')));
    expect(ws.read('apps/demo/lib/di/injection.dart'), isNot(contains('_a/')));
  });

  test('once nothing imports it, a second run deletes the API too', () async {
    final ws = workspace(bImportsApi: true);
    expect(await run(ws, ['a', '--apply']), exitsWith(0));
    ws.write({'modules/b/feature/pubspec.yaml': 'name: feature_b\n'});

    final again = await run(ws, ['a', '--apply']);
    expect(again, exitsWith(0));
    expect(again.output, isNot(contains('kept')));
    expect(exists(ws, 'modules/a'), isFalse);
    expect(
      ws.read('apps/demo/app_manifest.yaml'),
      isNot(contains('id: a,')),
    );
    expect(ws.read('pubspec.yaml'), isNot(contains('modules/a/')));
  });

  test('an API package nobody else imports goes with its module', () async {
    final ws = workspace(bImportsApi: false);
    final apply = await run(ws, ['a', '--apply']);
    expect(apply, exitsWith(0));
    expect(apply.output, isNot(contains('kept')));
    expect(exists(ws, 'modules/a'), isFalse);
    expect(
      ws.read('apps/demo/app_manifest.yaml'),
      isNot(contains('id: a,')),
    );
  });

  group('composer sync after --apply', () {
    // A stand-in composer: records that it ran, exits with the code a file asks.
    String stub(int exitCode) =>
        "import 'dart:io';\n"
        'void main(List<String> args) {\n'
        "  File('composer_ran.txt').writeAsStringSync(args.join(' '));\n"
        '  exit($exitCode);\n'
        '}\n';

    test('runs it, so the generated regions follow the manifests', () async {
      final ws = workspace(bImportsApi: false);
      ws.write({'tools/composer/composer.dart': stub(0)});
      final apply = await run(ws, ['a', '--apply']);
      expect(apply, exitsWith(0));
      expect(ws.read('composer_ran.txt'), 'sync');
      expect(apply.output, contains('composer sync: ok'));
      // Done: the next steps no longer ask for a sync the tool just did.
      expect(apply.output, isNot(contains('composer.dart sync')));
      expect(apply.output, contains('composer.dart verify'));
    });

    test('exits 1 with the next step when the composer refuses', () async {
      final ws = workspace(bImportsApi: false);
      ws.write({'tools/composer/composer.dart': stub(2)});
      final apply = await run(ws, ['a', '--apply']);
      expect(apply, exitsWith(1));
      expect(apply.output, contains('composer sync failed'));
      expect(apply.output, contains('dart tools/composer/composer.dart sync'));
    });

    test('a workspace without the composer lists it as a next step', () async {
      final apply = await run(workspace(bImportsApi: false), [
        'a',
        '--apply',
      ]);
      expect(apply, exitsWith(0));
      expect(apply.output, contains('dart tools/composer/composer.dart sync'));
    });
  });

  group('capabilities the bundle alone provided', () {
    TempWorkspace withCapabilities() {
      final ws = workspace(bImportsApi: false);
      ws.write({
        'tools/sample_manifest.yaml':
            'packages:\n'
            '  a_api: { kind: sample, path: modules/a/api }\n'
            '  domain_a: { kind: sample, path: modules/a/domain }\n'
            '  feature_a: { kind: sample, path: modules/a/feature }\n'
            '  feature_b: { kind: sample, path: modules/b/feature }\n'
            'bundles:\n'
            '  a:\n'
            '    packages: [feature_a, domain_a, a_api]\n'
            '    capabilities: [splash, session]\n'
            '    shared_capabilities: [routes]\n'
            '  b:\n'
            '    packages: [feature_b]\n',
        'apps/demo/app_manifest.yaml':
            'app:\n'
            '  id: demo\n'
            'capabilities:\n'
            '  session: provided # the sign-in bundle\n'
            '  splash: provided\n'
            '  routes: provided\n'
            '  analytics: { state: absent, reason: "no backend" }\n'
            'modules:\n'
            '  - { id: a, layers: [api, domain, feature] }\n'
            '  - { id: b, layers: [feature] }\n'
            'splash: provided\n',
      });
      return ws;
    }

    test('the dry run shows the flip', () async {
      final dry = await run(withCapabilities(), ['a']);
      expect(dry, exitsWith(0));
      expect(
        dry.output,
        contains(
          '+ session: { state: absent, reason: "sample a removed" }',
        ),
      );
      expect(
        dry.output,
        contains('+ splash: { state: absent, reason: "sample a removed" }'),
      );
    });

    test(
      '--apply flips them, and only them, to absent with a reason',
      () async {
        final ws = withCapabilities();
        final apply = await run(ws, ['a', '--apply']);
        expect(apply, exitsWith(0));

        final manifest = ws.read('apps/demo/app_manifest.yaml');
        expect(
          manifest,
          contains(
            '  session: { state: absent, reason: "sample a removed" }\n',
          ),
        );
        expect(
          manifest,
          contains('  splash: { state: absent, reason: "sample a removed" }\n'),
        );
        // The old comment described the old state; a shared contract and an
        // existing absence are left alone, and so is a `splash:` outside the
        // `capabilities:` block.
        expect(manifest, isNot(contains('the sign-in bundle')));
        expect(manifest, contains('  routes: provided\n'));
        expect(
          manifest,
          contains('  analytics: { state: absent, reason: "no backend" }\n'),
        );
        expect(manifest, contains('\nsplash: provided\n'));
      },
    );

    test('says which contracts the bundle shares', () async {
      final apply = await run(withCapabilities(), ['a', '--apply']);
      expect(apply.output, contains('also names routes'));
      expect(apply.output, contains('composer.dart verify'));
    });

    test('a bundle that lists none changes no capability', () async {
      final ws = withCapabilities();
      expect(await run(ws, ['b', '--apply']), exitsWith(0));
      expect(
        ws.read('apps/demo/app_manifest.yaml'),
        contains('  splash: provided\n'),
      );
    });
  });
}
