import 'package:test/test.dart';

import 'support/composer_fixture.dart';
import 'support/tool_harness.dart';

/// `tools/composer/composer.dart` — CI Gate 0 (`composer verify`).
///
/// The fixture (`support/composer_fixture.dart`) is one app (`demo`) composing
/// one module (`foo`, domain + feature) on top of `core_common`, with every
/// managed region present but empty. `sync` fills them; `verify` must then
/// agree. The manifest-v2 declaration has its own tests
/// (`composer_manifest_v2_test.dart`).
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
  }) => demoManifest(phase: phase, modules: modules);

  TempWorkspace workspace({String? appManifest}) =>
      TempWorkspace.create(demoWorkspaceFiles(manifest: appManifest));

  Future<ToolRun> run(TempWorkspace ws, List<String> args) =>
      tool.run(args, workingDirectory: ws.root);

  group('a package left on disk outside every composition', () {
    TempWorkspace stranded() => workspace()
      ..write({
        // Dropped from the manifest, directory left behind.
        'modules/bar/feature/pubspec.yaml': 'name: feature_bar\n',
        'modules/bar/feature/lib/di/module.dart': diModule(),
        // A platform package nothing composes or depends on.
        'platform/infra/unused/pubspec.yaml': 'name: core_unused\n',
      });

    test('fails verify, naming it and the fix', () async {
      final ws = stranded();
      expect(await run(ws, ['sync']), exitsWith(0));

      final verify = await run(ws, ['verify']);

      expect(verify, exitsWith(1));
      expect(
        verify.output,
        contains(
          "modules/bar/feature (feature_bar) is on disk but in no app's "
          'composition',
        ),
      );
      expect(verify.output, contains('platform/infra/unused (core_unused)'));
      expect(verify.output, contains('Delete it'));
      expect(verify.output, isNot(contains('up to date')));
    });

    test('is only a warning under sync, which still composes', () async {
      final ws = stranded();

      final sync = await run(ws, ['sync']);

      expect(sync, exitsWith(0));
      expect(sync.output, contains('modules/bar/feature (feature_bar)'));
      expect(ws.read('pubspec.yaml'), isNot(contains('modules/bar/feature')));
    });
  });

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

  test(
    'no command is a usage error: usage, exit 64 (never 1, the drift code)',
    () async {
      final ws = workspace();

      final none = await run(ws, const []);

      expect(none, exitsWith(64));
      expect(none.output, contains('USAGE'));
      expect(await run(ws, ['--help']), exitsWith(0));
      expect(await run(ws, ['nosuchcommand']), exitsWith(64));
    },
  );

  group('code outside the generated regions of injection.dart', () {
    const injection = 'apps/demo/lib/di/injection.dart';

    test(
      'a statement after the last region fails verify and survives sync',
      () async {
        final ws = workspace();
        expect(await run(ws, ['sync']), exitsWith(0));
        expect(await run(ws, ['verify']), exitsWith(0));

        ws.write({
          injection: '${ws.read(injection)}\nvoid handEdited() {}\n',
        });

        final verify = await run(ws, ['verify']);
        expect(verify, exitsWith(1));
        expect(verify.output, contains('$injection: injection: line '));
        expect(verify.output, contains('void handEdited() {}'));
        expect(verify.output, contains('V13'));

        // `sync` warns, still writes, and does not remove the line.
        final sync = await run(ws, ['sync']);
        expect(sync, exitsWith(0));
        expect(ws.read(injection), contains('void handEdited() {}'));
      },
    );

    test('a comment or blank line outside the regions is fine', () async {
      final ws = workspace();
      expect(await run(ws, ['sync']), exitsWith(0));

      ws.write({
        injection:
            '// A note for the reader.\n\n${ws.read(injection)}\n'
            '// Another one.\n',
      });

      expect(await run(ws, ['verify']), exitsWith(0));
    });
  });
}
