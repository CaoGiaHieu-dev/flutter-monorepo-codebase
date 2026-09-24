import 'package:test/test.dart';

import 'support/tool_harness.dart';

/// `tools/composer/composer.dart` — CI Gate 0 (`composer verify`).
///
/// The fixture is one app (`demo`) composing one module (`foo`, domain +
/// feature) on top of `core_common`, with every managed region present but
/// empty. `sync` fills them; `verify` must then agree.
void main() {
  late CompiledTool tool;

  setUpAll(() async {
    tool = await CompiledTool.compile('tools/composer/composer.dart');
  });
  tearDownAll(() => tool.dispose());

  const manifestPath = 'apps/demo/app_manifest.yaml';

  String manifest({
    String phase = 'before',
    String modules = '  - { id: foo, layers: [domain, feature] }\n',
  }) =>
      'app:\n'
      '  id: demo\n'
      'di_groups:\n'
      '  - name: core\n'
      '    phase: $phase\n'
      '    packages: [core_common]\n'
      '  - name: domain\n'
      '    phase: after\n'
      '    from_modules: domain\n'
      '  - name: feature\n'
      '    phase: after\n'
      '    from_modules: feature\n'
      'modules:\n'
      '$modules';

  String diModule() =>
      "import 'package:injectable/injectable.dart';\n\n"
      '@InjectableInit.microPackage()\n'
      'void initMicroPackage() {}\n';

  TempWorkspace workspace({String? appManifest}) => TempWorkspace.create({
    'pubspec.yaml':
        'name: ws\n'
        'workspace:\n'
        '  # composer:managed:workspace — generated from app_manifest.yaml\n'
        '  # composer:end:workspace\n',
    manifestPath: appManifest ?? manifest(),
    'apps/demo/pubspec.yaml':
        'name: demo_app\n'
        'resolution: workspace\n'
        'dependencies:\n'
        '  # composer:managed:deps — generated from app_manifest.yaml\n'
        '  # composer:end:deps\n',
    'apps/demo/lib/di/injection.dart':
        '// composer:managed:imports — generated from app_manifest.yaml\n'
        '// composer:end:imports\n'
        '\n'
        '// composer:managed:modules — generated from app_manifest.yaml\n'
        '// composer:end:modules\n',
    'platform/foundation/common/pubspec.yaml': 'name: core_common\n',
    'platform/foundation/common/lib/di/module.dart': diModule(),
    'modules/foo/domain/pubspec.yaml': 'name: domain_foo\n',
    'modules/foo/domain/lib/di/module.dart': diModule(),
    'modules/foo/feature/pubspec.yaml':
        'name: feature_foo\n'
        'dependencies:\n'
        '  domain_foo:\n'
        '    path: ../domain\n',
    'modules/foo/feature/lib/di/module.dart': diModule(),
  });

  Future<ToolRun> run(TempWorkspace ws, List<String> args) =>
      tool.run(args, workingDirectory: ws.root);

  group('a valid manifest', () {
    test('sync writes every region, then verify passes', () async {
      final ws = workspace();

      final sync = await run(ws, ['sync']);
      expect(sync, exitsWith(0));

      final injection = ws.read('apps/demo/lib/di/injection.dart');
      expect(injection, contains('ExternalModule(CoreCommonPackageModule)'));
      expect(injection, contains('ExternalModule(DomainFooPackageModule)'));
      expect(injection, contains('ExternalModule(FeatureFooPackageModule)'));
      expect(
        injection,
        contains("import 'package:feature_foo/di/module.module.dart';"),
      );
      expect(
        ws.read('apps/demo/pubspec.yaml'),
        contains('  feature_foo:\n    path: ../../modules/foo/feature'),
      );
      // A platform package sits one group folder deeper than a module layer.
      expect(
        ws.read('apps/demo/pubspec.yaml'),
        contains('  core_common:\n    path: ../../platform/foundation/common'),
      );
      final root = ws.read('pubspec.yaml');
      for (final member in [
        'apps/demo',
        'platform/foundation/common',
        'modules/foo/domain',
        'modules/foo/feature',
      ]) {
        expect(root, contains('  - $member\n'));
      }

      final verify = await run(ws, ['verify']);
      expect(verify, exitsWith(0));
      expect(verify.output, contains('Generated artifacts are up to date.'));
    });

    test(
      'an api layer is a workspace member only — no DI, no app dependency',
      () async {
        final ws = workspace(
          appManifest: manifest(
            modules: '  - { id: foo, layers: [api, domain, feature] }\n',
          ),
        );
        ws.write({'modules/foo/api/pubspec.yaml': 'name: foo_api\n'});

        final sync = await run(ws, ['sync']);
        expect(sync, exitsWith(0));
        expect(ws.read('pubspec.yaml'), contains('  - modules/foo/api\n'));
        expect(ws.read('apps/demo/pubspec.yaml'), isNot(contains('foo_api')));
        expect(
          ws.read('apps/demo/lib/di/injection.dart'),
          isNot(contains('FooApi')),
        );
        expect(await run(ws, ['verify']), exitsWith(0));
      },
    );

    test(
      'an api package reached only through a feature joins the workspace',
      () async {
        // What `remove_sample` leaves behind when it keeps an API package that
        // another module still imports: no manifest names it any more.
        final ws = workspace();
        ws.write({
          'modules/bar/api/pubspec.yaml': 'name: bar_api\n',
          'modules/foo/feature/pubspec.yaml':
              'name: feature_foo\n'
              'dependencies:\n'
              '  domain_foo:\n'
              '    path: ../domain\n'
              '  bar_api:\n'
              '    path: ../../bar/api\n',
        });

        expect(await run(ws, ['sync']), exitsWith(0));
        expect(ws.read('pubspec.yaml'), contains('  - modules/bar/api\n'));
      },
    );

    test('a missing api package fails verify (strict)', () async {
      final ws = workspace(
        appManifest: manifest(
          modules: '  - { id: foo, layers: [api, domain, feature] }\n',
        ),
      );
      final verify = await run(ws, ['verify']);
      expect(verify, exitsWith(1));
      expect(verify.output, contains('`foo/api` is declared by demo'));
    });

    test('verify fails on a hand-edited managed region', () async {
      final ws = workspace();
      expect(await run(ws, ['sync']), exitsWith(0));
      final path = 'apps/demo/lib/di/injection.dart';
      ws.write({
        path: ws
            .read(path)
            .replaceFirst('  ExternalModule(FeatureFooPackageModule),\n', ''),
      });

      final verify = await run(ws, ['verify']);
      expect(verify, exitsWith(1));
      expect(verify.output, contains('out of date: $path'));
    });

    test('verify fails when a declared module is not on disk', () async {
      final ws = workspace(
        appManifest: manifest(
          modules:
              '  - { id: foo, layers: [domain, feature] }\n'
              '  - { id: gone, layers: [feature] }\n',
        ),
      );
      final verify = await run(ws, ['verify']);
      expect(verify, exitsWith(1));
      expect(verify.output, contains('`gone/feature` is declared by demo'));
    });
  });

  group('a malformed manifest is refused with its key path', () {
    test('`phase: befor`', () async {
      final ws = workspace(appManifest: manifest(phase: 'befor'));
      final verify = await run(ws, ['verify']);
      expect(verify, exitsWith(1));
      expect(
        verify.output,
        contains(
          '$manifestPath: di_groups[0].phase: expected `before` or `after`, '
          'got a string (`befor`)',
        ),
      );
      expect(verify.output, contains('Nothing was written.'));
    });

    test('an unknown layer', () async {
      final ws = workspace(
        appManifest: manifest(
          modules: '  - { id: foo, layers: [domain, features] }\n',
        ),
      );
      final verify = await run(ws, ['verify']);
      expect(verify, exitsWith(1));
      expect(
        verify.output,
        contains(
          '$manifestPath: modules[0].layers[1]: expected one of '
          'api, domain, data, feature, got a string (`features`)',
        ),
      );
    });

    test('a duplicate module', () async {
      final ws = workspace(
        appManifest: manifest(
          modules:
              '  - { id: foo, layers: [domain] }\n'
              '  - { id: foo, layers: [feature] }\n',
        ),
      );
      final sync = await run(ws, ['sync']);
      expect(sync, exitsWith(1));
      expect(
        sync.output,
        contains(
          '$manifestPath: modules[1].id: module `foo` is listed more '
          'than once',
        ),
      );
      // Refused before anything is written.
      expect(ws.read('pubspec.yaml'), isNot(contains('  - apps/demo')));
    });
  });

  test('an unknown flag exits 64', () async {
    final ws = workspace();
    expect(await run(ws, ['sync', '--stritc']), exitsWith(64));
  });
}
