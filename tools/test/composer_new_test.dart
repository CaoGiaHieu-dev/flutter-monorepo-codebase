import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/composer_fixture.dart';
import 'support/tool_harness.dart';

/// `composer new`: a third app by command.
///
/// Run in a throwaway workspace that carries the real `app_template/` next to
/// the fixture packages, so the tests prove what the command is for:
///
/// - the app it writes passes `verify` at once, and `capabilities:` is derived
///   from what the requested modules register — absent ones carry the
///   catalog's `whenAbsent` text, never `TODO`;
/// - it refuses an existing id, a platform a requested module blocks, an
///   unknown module or platform, and in each case **writes nothing**;
/// - it never runs `flutter create`: no runner folder appears, and the command
///   to run is printed.
void main() {
  late CompiledTool composer;

  setUpAll(() async {
    composer = await CompiledTool.compile('tools/composer/composer.dart');
  });
  tearDownAll(() => composer.dispose());

  /// The packages every new app composes, as empty pubspecs: `new` needs them
  /// on disk, not their contents.
  const shared = {
    'platform/infra/network': 'core_network',
    'platform/infra/storage': 'core_storage',
    'platform/foundation/contracts': 'core_di',
    'platform/shell/adapters': 'platform_shell_adapters',
    'platform/ui/design_system': 'core_base_ui',
    'platform/layers/domain': 'domain_core',
    'platform/layers/data': 'data_core',
    'platform/state/provider': 'provider_state_management',
    'platform/state/bloc': 'bloc_state_management',
  };

  /// `core_database` as the repository declares it: no web (drift/native needs
  /// dart:ffi).
  const databasePubspec =
      'name: core_database\n'
      'platforms:\n'
      '  android:\n'
      '  ios:\n'
      '  macos:\n'
      '  windows:\n'
      '  linux:\n';

  /// The real app template, copied into the workspace.
  Map<String, String> template() {
    final dir = Directory(
      p.join(repoRoot, 'tools', 'composer', 'app_template'),
    );
    return {
      for (final file in dir.listSync(recursive: true).whereType<File>())
        p.posix.join(
          'tools/composer/app_template',
          p.posix.joinAll(p.split(p.relative(file.path, from: dir.path))),
        ): file
            .readAsStringSync(),
    };
  }

  /// The `demo` app, composing `foo` (registers `session` and `routes`) and
  /// `bar` (opens a database, so it links `core_database`), so that nothing in
  /// the workspace is left uncomposed for `verify` to complain about.
  String demoWithDatabase() =>
      demoManifest(
            modules:
                '  - { id: foo, layers: [domain, feature] }\n'
                '  - { id: bar, layers: [data] }\n',
          )
          .replaceFirst(
            'packages: [core_common]',
            'packages: [core_common, core_database]',
          )
          .replaceFirst(
            '  - name: feature\n',
            '  - name: data\n    phase: after\n    from_modules: data\n'
                '  - name: feature\n',
          );

  /// The `demo` workspace plus everything `new` composes — the shared
  /// packages, the template, a module that opens a database and a pubspec
  /// catalog — already synced, as a repository is.
  Future<TempWorkspace> workspace() async {
    final ws = TempWorkspace.create({
      ...demoWorkspaceFiles(
        manifest: demoWithDatabase(),
        extra: {
          for (final entry in shared.entries) ...{
            '${entry.key}/pubspec.yaml': 'name: ${entry.value}\n',
            '${entry.key}/lib/di/module.dart': diModule(),
          },
          'platform/infra/database/pubspec.yaml': databasePubspec,
          'platform/infra/database/lib/di/module.dart': diModule(),
          'modules/bar/data/pubspec.yaml':
              'name: data_bar\n'
              'dependencies:\n'
              '  core_database:\n'
              '    path: ../../../platform/infra/database\n',
          'modules/bar/data/lib/di/module.dart': diModule(),
          'pubspec_dependencies.yaml':
              'dependencies:\n'
              '  injectable: "^3.0.0"\n'
              'dev_dependencies:\n'
              '  flutter_secure_storage: "11.2.0"\n'
              '  shared_preferences: "^2.5.5"\n'
              '  build_runner: "^2.16.0"\n'
              '  injectable_generator: "^3.1.3"\n'
              '  flutter_lints: "^6.0.0"\n',
        },
      ),
      ...template(),
    });
    expect(
      await composer.run(['sync'], workingDirectory: ws.root),
      exitsWith(0),
    );
    return ws;
  }

  Future<ToolRun> run(TempWorkspace ws, List<String> args) =>
      composer.run(args, workingDirectory: ws.root);

  /// Every file under the workspace with its content, so a refusal can be shown
  /// to have changed nothing.
  Map<String, String> snapshot(TempWorkspace ws) => {
    for (final file in Directory(ws.root).listSync(recursive: true))
      if (file is File)
        p.relative(file.path, from: ws.root): file.readAsStringSync(),
  };

  group('a new app', () {
    test('is written, composed and passes verify at once', () async {
      final ws = await workspace();
      final result = await run(ws, [
        'new',
        'reports',
        '--name',
        'Codebase Reports',
        '--platforms',
        'web,windows',
        '--modules',
        'foo',
      ]);
      expect(result, exitsWith(0));

      for (final file in [
        'app_manifest.yaml',
        'pubspec.yaml',
        'README.md',
        'env.dev',
        '.gitignore',
        'lib/main.dart',
        'lib/app/app_profile.dart',
        'lib/app/app_hooks.dart',
        'lib/di/injection.dart',
        'test/di_smoke_test.dart',
        'test/app_profile_test.dart',
      ]) {
        expect(ws.exists('apps/reports/$file'), isTrue, reason: file);
      }

      expect(await run(ws, ['verify']), exitsWith(0));
      final describe = await run(ws, ['describe', '--app', 'reports']);
      expect(describe, exitsWith(0));
      expect(describe.stdout, contains('## reports — Codebase Reports'));
    });

    test('has its generated regions filled in', () async {
      final ws = await workspace();
      expect(
        await run(ws, [
          'new',
          'reports',
          '--platforms',
          'web,windows',
          '--modules',
          'foo',
        ]),
        exitsWith(0),
      );

      expect(
        ws.read('apps/reports/lib/app/app_profile.dart'),
        contains("const AppFacts appFacts = AppFacts(\n  id: 'reports',"),
      );
      expect(
        ws.read('apps/reports/lib/di/injection.dart'),
        contains('Future<void> configureDependencies'),
      );
      expect(
        ws.read('apps/reports/pubspec.yaml'),
        contains('feature_foo:'),
        reason: 'the requested module is a dependency',
      );
      expect(
        ws.read('pubspec.yaml'),
        contains('apps/reports'),
        reason: 'and the app joins the root workspace',
      );
      expect(
        ws.read('apps/reports/README.md'),
        contains('## reports — Reports'),
        reason: 'the name defaults to the id, title-cased',
      );
    });

    test('derives its capabilities from what the modules register', () async {
      final ws = await workspace();
      expect(
        await run(ws, [
          'new',
          'reports',
          '--platforms',
          'windows',
          '--modules',
          'foo',
        ]),
        exitsWith(0),
      );
      final manifest = ws.read('apps/reports/app_manifest.yaml');

      // `foo` registers the session bundle and `routes`.
      expect(manifest, contains('  session: provided\n'));
      expect(manifest, contains('  routes: provided\n'));
      // Nothing registers a splash: absent, with what the shell does instead —
      // the catalog's text, never a placeholder.
      expect(
        manifest,
        contains(
          '  splash: { state: absent, reason: '
          '"the native splash is kept" }\n',
        ),
      );
      expect(manifest, isNot(contains('TODO')));
      expect(manifest, isNot(contains('TBD')));
      // Every platform is a runner still to be created.
      expect(manifest, contains('  windows: { runner: scaffold }\n'));
    });

    test('with no modules, every optional contract is absent', () async {
      final ws = await workspace();
      expect(
        await run(ws, ['new', 'bare', '--platforms', 'linux']),
        exitsWith(0),
      );
      final manifest = ws.read('apps/bare/app_manifest.yaml');
      expect(manifest, contains('modules: []'));
      expect(manifest, contains('  session: { state: absent'));
      expect(await run(ws, ['verify']), exitsWith(0));
    });

    test('says so when no module contributes a screen', () async {
      final ws = await workspace();
      final bare = await run(ws, ['new', 'bare', '--platforms', 'linux']);
      expect(bare, exitsWith(0));
      expect(bare.output, contains('No composed module contributes a screen'));
      expect(bare.output, contains('C05'));

      final withScreen = await run(ws, [
        'new',
        'shown',
        '--platforms',
        'linux',
        '--modules',
        'foo',
      ]);
      expect(withScreen, exitsWith(0));
      expect(
        withScreen.output,
        isNot(contains('No composed module contributes a screen')),
      );
    });

    test('composes core_database when a module links it', () async {
      final ws = await workspace();
      expect(
        await run(ws, [
          'new',
          'ledger',
          '--platforms',
          'windows',
          '--modules',
          'bar',
        ]),
        exitsWith(0),
      );
      expect(
        ws.read('apps/ledger/app_manifest.yaml'),
        contains('- core_database'),
      );
      expect(await run(ws, ['verify']), exitsWith(0));
    });

    test('gives the smoke test of a database app its own doubles', () async {
      final ws = await workspace();
      expect(
        await run(ws, [
          'new',
          'ledger',
          '--platforms',
          'windows',
          '--modules',
          'bar',
        ]),
        exitsWith(0),
      );
      final smoke = ws.read('apps/ledger/test/di_smoke_test.dart');
      expect(smoke, contains("import 'dart:io';"));
      expect(
        smoke,
        contains("import 'package:drift/drift.dart' show GeneratedDatabase;"),
      );
      expect(smoke, contains('plugins.flutter.io/path_provider'));
      expect(smoke, contains('getIt.findAll<GeneratedDatabase>()'));
      expect(ws.read('apps/ledger/pubspec.yaml'), contains('  drift: '));

      // An app that links no database carries none of it.
      expect(
        await run(ws, ['new', 'plain', '--platforms', 'linux']),
        exitsWith(0),
      );
      final plain = ws.read('apps/plain/test/di_smoke_test.dart');
      expect(plain, isNot(contains('path_provider\')')));
      expect(plain, isNot(contains('GeneratedDatabase')));
      expect(ws.read('apps/plain/pubspec.yaml'), isNot(contains('drift')));
    });

    test(
      'decides the pin of staging and prod where a platform can pin',
      () async {
        final ws = await workspace();
        expect(
          await run(ws, ['new', 'phone', '--platforms', 'android,ios']),
          exitsWith(0),
        );
        final manifest = ws.read('apps/phone/app_manifest.yaml');
        expect(
          manifest,
          contains('ssl_pinning: { disabled: "no SPKI pins provisioned yet'),
        );
        expect(await run(ws, ['verify']), exitsWith(0));
      },
    );

    test('sorts the smoke test imports for its own id', () async {
      final ws = await workspace();
      expect(
        await run(ws, ['new', 'zeta', '--platforms', 'windows']),
        exitsWith(0),
      );
      final smoke = ws.read('apps/zeta/test/di_smoke_test.dart');
      final imports = [
        for (final line in smoke.split('\n'))
          if (line.startsWith('import ')) line,
      ];
      expect(imports, [...imports]..sort());
      expect(
        imports.indexOf("import 'package:zeta_app/di/injection.dart';"),
        greaterThan(
          imports.indexOf(
            "import 'package:shared_preferences/shared_preferences.dart';",
          ),
        ),
      );
    });

    test('names a declared platform in its smoke test, not the web', () async {
      final ws = await workspace();
      expect(
        await run(ws, ['new', 'reports', '--platforms', 'web,windows']),
        exitsWith(0),
      );
      expect(
        ws.read('apps/reports/test/di_smoke_test.dart'),
        contains('const _platform = AppPlatform.windows;'),
      );
    });
  });

  group('never runs flutter create', () {
    test('writes no runner and prints the line to run', () async {
      final ws = await workspace();
      final result = await run(ws, [
        'new',
        'reports',
        '--platforms',
        'web,windows',
        '--modules',
        'foo',
      ]);
      expect(result, exitsWith(0));

      for (final folder in ['web', 'windows', 'android', 'ios', 'linux']) {
        expect(ws.exists('apps/reports/$folder'), isFalse, reason: folder);
      }
      expect(result.output, contains('does NOT run `flutter create`'));
      expect(
        result.output,
        contains(
          'cd apps/reports && flutter create --platforms=web,windows '
          '--org com.example --project-name reports_app .',
        ),
      );
    });
  });

  group('refuses, and writes nothing', () {
    Future<void> refused(
      List<String> args,
      Matcher message, {
      int exitCode = 1,
    }) async {
      final ws = await workspace();
      final before = snapshot(ws);
      final result = await run(ws, args);
      expect(result, exitsWith(exitCode));
      expect(result.output, message);
      expect(snapshot(ws), before, reason: 'a refusal must leave no trace');
    }

    test('an id that is already an app', () async {
      await refused(
        ['new', 'demo', '--platforms', 'web'],
        contains('app id `demo`: already the id of an app'),
      );
    });

    test('a platform a requested module blocks', () async {
      await refused(
        ['new', 'ledger', '--platforms', 'web,windows', '--modules', 'bar'],
        allOf(
          contains('core_database does not support web'),
          contains('module `bar` links it (data_bar -> core_database)'),
        ),
      );
    });

    test('an unknown module', () async {
      await refused(
        ['new', 'reports', '--platforms', 'web', '--modules', 'nope'],
        contains('no module named `nope`'),
      );
    });

    test('an unknown platform', () async {
      await refused(
        ['new', 'reports', '--platforms', 'amiga'],
        contains('`amiga` is not a platform'),
      );
    });

    test('an id that is not a package name', () async {
      await refused(
        ['new', 'Reports', '--platforms', 'web'],
        contains('app id `Reports`'),
      );
    });

    test('a name that would break the files it is written into', () async {
      await refused(
        ['new', 'reports', '--platforms', 'web', '--name', 'Bob\'s "Reports"'],
        contains('--name: expected a display name without quotes'),
      );
    });

    test('a missing --platforms', () async {
      await refused(
        ['new', 'reports'],
        contains('`new` needs `--platforms`'),
        exitCode: 64,
      );
    });

    test('a missing id', () async {
      await refused(
        ['new', '--platforms', 'web'],
        contains('`new` needs an app id'),
        exitCode: 64,
      );
    });

    test('an app template that is not there', () async {
      final ws = await workspace();
      Directory(p.join(ws.root, 'tools', 'composer', 'app_template'))
          .deleteSync(recursive: true);
      final before = snapshot(ws);
      final result = await run(ws, ['new', 'reports', '--platforms', 'web']);
      expect(result, exitsWith(1));
      expect(result.output, contains('the app template is not at'));
      expect(snapshot(ws), before);
    });
  });
}
