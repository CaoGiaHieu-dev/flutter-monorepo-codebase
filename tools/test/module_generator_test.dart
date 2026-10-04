import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../module_generator/src/common_helpers.dart';
import '../module_generator/src/module_type.dart';
import '../module_generator/src/pubspec_generator.dart';
import 'support/composer_fixture.dart';
import 'support/fake_bin.dart';
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
  name: Mobile

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

    test('an app created with no modules (`modules: []`) can be extended', () {
      // What `composer new` writes for an app that composes no module: the
      // generator used to find no `modules:` list in the expected format and
      // roll the whole generation back.
      final ws = TempWorkspace.create({
        'pubspec.yaml': 'name: ws\nworkspace:\n  - apps/kiosk\n',
        'apps/kiosk/app_manifest.yaml': '''
app:
  id: kiosk

di_groups:
  - name: core
    phase: before
    packages: [core_common]

# Modules this app composes.
modules: []

# `extra_dependencies:` (optional)
''',
        'apps/kiosk/pubspec.yaml': 'name: kiosk_app\n',
      });
      CommonHelpers.registerInAppManifests(
        'feature_panel',
        ModuleType.feature,
        'panel',
        apps: const ['kiosk'],
        root: ws.root,
      );
      CommonHelpers.registerInAppManifests(
        'domain_panel',
        ModuleType.domain,
        'panel',
        apps: const ['kiosk'],
        root: ws.root,
      );

      final manifest = ws.read('apps/kiosk/app_manifest.yaml');
      expect(manifest, isNot(contains('modules: []')));
      expect(manifest, contains('modules:\n  - { id: panel, layers: '));
      expect(manifest, contains('feature'));
      expect(manifest, contains('domain'));
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

  group('package descriptions say what the package is', () {
    ModuleConfig config(ModuleType type, {String name = 'notes'}) =>
        ModuleConfig(
          type: type,
          typeDir: '',
          typeName: '',
          nameInput: name,
          smType: StateManagementType.none,
          moduleName: 'x_$name',
          modulePath: 'modules/$name/x',
        );

    test('one sentence per type, naming the module, never a placeholder', () {
      final all = {
        for (final type in ModuleType.values)
          type: PubspecGenerator.describe(config(type)),
      };

      expect(
        all[ModuleType.feature],
        startsWith('Presentation layer of the notes'),
      );
      expect(all[ModuleType.domain], startsWith('Domain layer of the notes'));
      expect(all[ModuleType.data], startsWith('Data layer of the notes'));
      expect(all[ModuleType.api], startsWith('Public API of the notes'));
      for (final description in all.values) {
        expect(description, isNot(startsWith('Module ')));
        expect(description, isNot(contains('"')));
      }
    });
  });

  // The rendered output of the paths the CI smoke jobs do not reach (the
  // others are `1 smoke "" 2 2`, `1 smoke_p "" 1 1`, 6, 2 and 3 with a
  // domain). Every external command goes to a fake `dart` / `flutter`, so what
  // is asserted here is what the generator itself writes: the files, their
  // content and the pubspec. Whether the result compiles is the smoke job's.
  group('generation renders every template path', () {
    final skip = skipWithoutPosixShell();

    /// The real templates, copied beside the snapshot: the generator reads
    /// them relative to its own location.
    Map<String, String> templates() {
      final root = p.join(repoRoot, 'tools', 'module_generator', 'templates');
      return {
        for (final file in Directory(root).listSync(recursive: true))
          if (file is File)
            'tools/module_generator/templates/${p.relative(file.path, from: root).replaceAll(r'\', '/')}':
                file.readAsStringSync(),
      };
    }

    String stub(String name) => 'name: $name\n';

    TempWorkspace generationWorkspace({Map<String, String> extra = const {}}) =>
        TempWorkspace.create({
          'pubspec.yaml': 'name: ws\nenvironment:\n  sdk: ">=3.13.3 <4.0.0"\n  flutter: ">=3.47.4"\nworkspace:\n  - apps/mobile\n',
          'apps/mobile/app_manifest.yaml': '''
app:
  id: mobile
  name: Mobile

di_groups:
  - name: core
    phase: before
    packages:
      - core_common

modules: []
''',
          'apps/mobile/pubspec.yaml': stub('mobile'),
          for (final (dir, name) in [
            ('platform/foundation/contracts', 'core_di'),
            ('platform/foundation/common', 'core_common'),
            ('platform/ui/design_system', 'core_base_ui'),
            ('platform/ui/responsive', 'core_responsive'),
            ('platform/ui/ui_kit', 'core_ui_kit'),
            ('platform/state/provider', 'provider_state_management'),
            ('platform/state/bloc', 'bloc_state_management'),
            ('platform/layers/domain', 'domain_core'),
            ('platform/layers/data', 'data_core'),
          ])
            '$dir/pubspec.yaml': stub(name),
          ...templates(),
          ...extra,
        });

    FakeBin toolchain() =>
        FakeBin.create({'dart': 'exit 0', 'flutter': 'exit 0'});

    Future<ToolRun> generate(
      TempWorkspace ws,
      List<String> args, {
      FakeBin? bin,
    }) => tool.run(
      args,
      workingDirectory: ws.root,
      scriptPath: 'tools/module_generator/generate.dill',
      environment: (bin ?? toolchain()).environment,
    );

    bool exists(TempWorkspace ws, String path) =>
        File(p.join(ws.root, path)).existsSync() ||
        Directory(p.join(ws.root, path)).existsSync();

    test('a feature with no state management and no route (1 x "" 3 3)', () async {
      final ws = generationWorkspace();

      final run = await generate(ws, ['1', 'plain', '', '3', '3']);

      expect(run, exitsWith(0));
      const feature = 'modules/plain/feature';
      expect(exists(ws, '$feature/lib/src/pages/plain_page.dart'), isTrue);
      expect(exists(ws, '$feature/lib/di/module.dart'), isTrue);
      expect(exists(ws, '$feature/assets/language/en.arb'), isTrue);
      expect(exists(ws, '$feature/assets/language/vi.arb'), isTrue);
      // No controller and no route-contribution stub of either kind (the
      // typed route itself belongs to the page, so `routing/` is not empty).
      expect(
        exists(ws, '$feature/lib/src/routing/plain_route_module.dart'),
        isTrue,
      );
      expect(
        exists(ws, '$feature/lib/src/routing/plain_feature_route_module.dart'),
        isFalse,
      );
      expect(
        exists(ws, '$feature/lib/src/routing/plain_nav_destination.dart'),
        isFalse,
      );
      // The page test is still there and builds the page without a controller.
      final pageTest = ws.read('$feature/test/plain_page_test.dart');
      expect(pageTest, isNot(contains('ChangeNotifierProvider')));
      expect(pageTest, isNot(contains('BlocProvider')));
      expect(exists(ws, '$feature/test/plain_provider_test.dart'), isFalse);
      expect(exists(ws, '$feature/test/plain_bloc_test.dart'), isFalse);

      final pubspec = ws.read('$feature/pubspec.yaml');
      expect(pubspec, contains('name: feature_plain'));
      expect(
        pubspec,
        contains('description: "Presentation layer of the plain module'),
      );
      expect(pubspec, isNot(contains('provider_state_management')));
      expect(pubspec, isNot(contains('bloc_state_management')));
      expect(pubspec, isNot(contains('freezed')));
      expect(pubspec, contains('core_responsive:'));
      // Mustache section tags leave nothing behind.
      expect(pubspec, isNot(contains('{{')));
      // The module is composed into the app, and the toolchain was driven.
      expect(
        ws.read('apps/mobile/app_manifest.yaml'),
        contains('id: plain'),
      );
    }, skip: skip);

    test('a BLoC feature with a stack route (1 x "" 2 1)', () async {
      final ws = generationWorkspace();

      final run = await generate(ws, ['1', 'chat', '', '2', '1']);

      expect(run, exitsWith(0));
      const feature = 'modules/chat/feature';
      for (final file in ['bloc', 'event', 'state']) {
        expect(exists(ws, '$feature/lib/src/bloc/chat_$file.dart'), isTrue);
      }
      expect(
        exists(ws, '$feature/lib/src/routing/chat_feature_route_module.dart'),
        isTrue,
      );
      expect(
        exists(ws, '$feature/lib/src/routing/chat_nav_destination.dart'),
        isFalse,
      );
      expect(exists(ws, '$feature/test/chat_bloc_test.dart'), isTrue);
      final pubspec = ws.read('$feature/pubspec.yaml');
      expect(pubspec, contains('bloc_state_management:'));
      expect(pubspec, contains('freezed'));
    }, skip: skip);

    test(
      'data without a domain: the repository implements no interface',
      () async {
        final ws = generationWorkspace();

        final run = await generate(ws, ['3', 'orders']);

        expect(run, exitsWith(0));
        expect(run.output, contains('No domain_orders yet'));
        const data = 'modules/orders/data';
        final impl = ws.read(
          '$data/lib/src/repositories_impl/orders_repository_impl.dart',
        );
        expect(
          impl,
          contains('class OrdersRepositoryImpl extends BaseRepository {}'),
        );
        expect(impl, isNot(contains("import 'package:domain_orders")));
        final pubspec = ws.read('$data/pubspec.yaml');
        expect(pubspec, contains('data_core:'));
        expect(pubspec, isNot(contains('domain_orders')));
        expect(
          pubspec,
          contains('description: "Data layer of the orders module'),
        );
      },
      skip: skip,
    );

    test('data with its domain implements the domain repository', () async {
      final ws = generationWorkspace(
        extra: {'modules/orders/domain/pubspec.yaml': stub('domain_orders')},
      );

      final run = await generate(ws, ['3', 'orders']);

      expect(run, exitsWith(0));
      expect(run.output, isNot(contains('No domain_orders yet')));
      const data = 'modules/orders/data';
      final impl = ws.read(
        '$data/lib/src/repositories_impl/orders_repository_impl.dart',
      );
      expect(impl, contains('domain_orders'));
      expect(impl, contains('implements'));
      expect(ws.read('$data/pubspec.yaml'), contains('domain_orders:'));
    }, skip: skip);

    test('a core package (4) lands in platform/infra with no workspace '
        'dependency, and joins the core group', () async {
      final ws = generationWorkspace();

      final run = await generate(ws, ['4', 'metrics']);

      expect(run, exitsWith(0));
      final pubspec = ws.read('platform/infra/metrics/pubspec.yaml');
      expect(pubspec, contains('name: core_metrics'));
      expect(pubspec, contains('description: "Platform package metrics'));
      expect(pubspec, isNot(contains('path:')));
      expect(exists(ws, 'platform/infra/metrics/lib/di/module.dart'), isTrue);
      expect(exists(ws, 'platform/infra/metrics/lib/src/pages'), isFalse);
      expect(
        ws.read('apps/mobile/app_manifest.yaml'),
        contains('core_metrics'),
      );
    }, skip: skip);

    test(
      'a custom package (5) is <prefix>_<name> in the chosen group',
      () async {
        final ws = generationWorkspace();

        final run = await generate(ws, [
          '5',
          'ledger',
          'acme',
          '--group',
          'ui',
        ]);

        expect(run, exitsWith(0));
        final pubspec = ws.read('platform/ui/ledger/pubspec.yaml');
        expect(pubspec, contains('name: acme_ledger'));
        expect(pubspec, isNot(contains('path:')));
        expect(exists(ws, 'platform/ui/ledger/lib/di/module.dart'), isTrue);
        expect(
          ws.read('apps/mobile/app_manifest.yaml'),
          contains('acme_ledger'),
        );
      },
      skip: skip,
    );

    test('a failing toolchain step rolls the shared files back', () async {
      final ws = generationWorkspace();
      final before = ws.read('apps/mobile/app_manifest.yaml');
      final bin = FakeBin.create({
        'dart': 'exit 0',
        'flutter': 'case "\$*" in "pub get") exit 1 ;; esac\nexit 0',
      });

      final run = await generate(ws, ['4', 'metrics'], bin: bin);

      expect(run, exitsWith(1));
      expect(ws.read('apps/mobile/app_manifest.yaml'), before);
    }, skip: skip);
  });

  // `composer sync` rewrites each app's README `report` region and
  // `app_profile.dart` `facts` region as well as the manifests' children, so
  // a run killed after the sync must restore those too — otherwise the
  // rolled-back tree is red under `composer verify`.
  group('a rolled-back run leaves composer verify green', () {
    final skip = skipWithoutPosixShell();
    late CompiledTool composer;

    setUpAll(() async {
      composer = await CompiledTool.compile('tools/composer/composer.dart');
    });
    tearDownAll(() => composer.dispose());

    /// The `demo` workspace of the composer tests, plus the generator's own
    /// templates, synced once the way a repository is.
    Future<TempWorkspace> syncedWorkspace() async {
      final templateRoot = p.join(
        repoRoot,
        'tools',
        'module_generator',
        'templates',
      );
      final ws = TempWorkspace.create({
        ...demoWorkspaceFiles(),
        for (final file in Directory(templateRoot).listSync(recursive: true))
          if (file is File)
            'tools/module_generator/templates/${p.relative(file.path, from: templateRoot).replaceAll(r'\', '/')}':
                file.readAsStringSync(),
      });
      expect(
        await composer.run(['sync'], workingDirectory: ws.root),
        exitsWith(0),
      );
      return ws;
    }

    test('killed after composer sync, before the toolchain', () async {
      final ws = await syncedWorkspace();
      expect(
        await composer.run(['verify'], workingDirectory: ws.root),
        exitsWith(0),
      );
      const tracked = [
        'pubspec.yaml',
        'apps/demo/app_manifest.yaml',
        'apps/demo/pubspec.yaml',
        'apps/demo/lib/di/injection.dart',
        'apps/demo/lib/app/app_profile.dart',
        'apps/demo/README.md',
      ];
      final before = {for (final path in tracked) path: ws.read(path)};

      // `dart` runs the real composer, so `sync` rewrites the regions for
      // real; dependency_sync, the step after it, is the one that dies.
      final bin = FakeBin.create({
        'dart':
            'case "\$1" in\n'
            '  tools/composer/composer.dart) shift\n'
            '    exec "$dartExecutable" "${composer.dill}" "\$@" ;;\n'
            '  tools/dependency_sync.dart) exit 1 ;;\n'
            'esac\n'
            'exit 0',
        'flutter': 'exit 0',
      });

      final run = await tool.run(
        ['2', 'chat'],
        workingDirectory: ws.root,
        scriptPath: 'tools/module_generator/generate.dill',
        environment: bin.environment,
      );

      expect(run, exitsWith(1));
      // The sync really ran: it registered the module before the failure.
      expect(bin.argsOf('dart'), contains('tools/composer/composer.dart sync'));
      for (final path in tracked) {
        expect(ws.read(path), before[path], reason: '$path was not restored');
      }
      expect(
        Directory(p.join(ws.root, 'modules', 'chat')).existsSync(),
        isFalse,
      );
      expect(
        await composer.run(['verify'], workingDirectory: ws.root),
        exitsWith(0),
      );
    }, skip: skip);
  });

  group('the generated navigator keeps its imports sorted', () {
    test('a name that sorts before flutter and injectable', () {
      final out = CommonHelpers.sortLeadingPackageImports(
        "import 'package:flutter/widgets.dart';\n"
        "import 'package:injectable/injectable.dart';\n"
        "import 'package:alpha_api/alpha_api.dart';\n"
        '\n'
        "import '../route.dart';\n",
      );
      expect(
        out.split('\n').take(3),
        [
          "import 'package:alpha_api/alpha_api.dart';",
          "import 'package:flutter/widgets.dart';",
          "import 'package:injectable/injectable.dart';",
        ],
      );
      expect(out, endsWith("import '../route.dart';\n"));
    });

    test('a name that sorts between them, and source without imports', () {
      final out = CommonHelpers.sortLeadingPackageImports(
        "import 'package:flutter/widgets.dart';\n"
        "import 'package:injectable/injectable.dart';\n"
        "import 'package:home_api/home_api.dart';\n",
      );
      expect(out.split('\n').take(3), [
        "import 'package:flutter/widgets.dart';",
        "import 'package:home_api/home_api.dart';",
        "import 'package:injectable/injectable.dart';",
      ]);
      expect(
        CommonHelpers.sortLeadingPackageImports('class A {}'),
        'class A {}',
      );
    });
  });
}
