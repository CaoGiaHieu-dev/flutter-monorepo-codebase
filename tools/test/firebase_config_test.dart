import 'package:test/test.dart';

import '../firebase/firebase_config.dart';
import 'support/tool_harness.dart';

/// `tools/firebase/firebase_config.dart` — per-app FlutterFire configuration.
///
/// The real work needs the Firebase CLI, a login and a terminal, none of
/// which a test has. What is covered is everything decided before the first
/// prompt (arguments, which app, the terminal check) as a process against a
/// temp workspace, and the per-flavor bundle-id mapping as a pure function.
void main() {
  group('flavorBundleIds', () {
    test('prod is the base id on both platforms', () {
      final ids = flavorBundleIds('com.example.codebase', 'prod');

      expect(ids.ios, 'com.example.codebase');
      expect(ids.android, 'com.example.codebase');
    });

    test('`production` is treated as prod', () {
      final ids = flavorBundleIds('com.example.codebase', 'production');

      expect(ids.ios, 'com.example.codebase');
      expect(ids.android, 'com.example.codebase');
    });

    test('staging is `.staging` on iOS but `.stg` on Android', () {
      // Gradle's applicationIdSuffix and the Xcode bundle id differ; each
      // Firebase client must match the id its platform builds.
      final ids = flavorBundleIds('com.example.codebase', 'staging');

      expect(ids.ios, 'com.example.codebase.staging');
      expect(ids.android, 'com.example.codebase.stg');
    });

    test('a flavor without a special suffix uses its own name', () {
      final ids = flavorBundleIds('com.example.codebase', 'dev');

      expect(ids.ios, 'com.example.codebase.dev');
      expect(ids.android, 'com.example.codebase.dev');
    });

    test('a custom flavor is suffixed with its name', () {
      final ids = flavorBundleIds('com.acme.app', 'qa');

      expect(ids.ios, 'com.acme.app.qa');
      expect(ids.android, 'com.acme.app.qa');
    });
  });

  group('as a process', () {
    late CompiledTool tool;
    setUpAll(() async {
      tool = await CompiledTool.compile('tools/firebase/firebase_config.dart');
    });
    tearDownAll(() => tool.dispose());

    const manifest = 'app:\n  id: mobile\n';

    TempWorkspace single({Map<String, String> more = const {}}) =>
        TempWorkspace.create({
          'pubspec.yaml': 'name: ws\nworkspace:\n  - apps/mobile\n',
          'apps/mobile/app_manifest.yaml': manifest,
          ...more,
        });

    Future<ToolRun> run(TempWorkspace ws, [List<String> args = const []]) =>
        tool.run(args, workingDirectory: ws.root);

    test('--help prints the usage and exits 0', () async {
      final run0 = await run(single(), ['--help']);

      expect(run0, exitsWith(0));
      expect(
        run0.stdout,
        contains('Usage: dart tools/firebase/firebase_config.dart'),
      );
      expect(run0.stdout, contains('--app <id>'));
      expect(run0.stdout, contains('google-services.json'));
    });

    test('-h is the same as --help', () async {
      final run0 = await run(single(), ['-h']);

      expect(run0, exitsWith(0));
      expect(run0.stdout, contains('Usage:'));
    });

    test('an unknown argument exits 64 with the usage', () async {
      final run0 = await run(single(), ['--project', 'x']);

      expect(run0, exitsWith(64));
      expect(run0.output, contains('Unknown argument: --project'));
      expect(run0.stderr, contains('Usage:'));
    });

    test('outside a repository root exits 1', () async {
      final ws = TempWorkspace.create({
        'apps/mobile/app_manifest.yaml': manifest,
      });

      final run0 = await run(ws);

      expect(run0, exitsWith(1));
      expect(run0.output, contains('run this script from the project root'));
    });

    test('a workspace without an app exits 1', () async {
      final ws = TempWorkspace.create({'pubspec.yaml': 'name: ws\n'});

      final run0 = await run(ws);

      expect(run0, exitsWith(1));
      expect(run0.output, contains('No app found'));
    });

    test('several apps without --app exit 64 and list them', () async {
      final ws = single(
        more: {'apps/admin/app_manifest.yaml': 'app:\n  id: admin\n'},
      );

      final run0 = await run(ws);

      expect(run0, exitsWith(64));
      expect(run0.output, contains('2 apps found; say which one with --app'));
      expect(run0.output, contains('- admin  (apps/admin)'));
      expect(run0.output, contains('- mobile  (apps/mobile)'));
    });

    test('--app without an id exits 64', () async {
      final run0 = await run(single(), ['--app']);

      expect(run0, exitsWith(64));
      expect(run0.output, contains('--app needs an id'));
    });

    test(
      '--app with an unknown id exits 64 and lists the known apps',
      () async {
        final run0 = await run(single(), ['--app', 'ghost']);

        expect(run0, exitsWith(64));
        expect(run0.output, contains('No app with id "ghost"'));
        expect(run0.output, contains('- mobile  (apps/mobile)'));
      },
    );

    test(
      'a run without a terminal stops before any prompt with exit 1',
      () async {
        final run0 = await run(single(), ['--app', 'mobile']);

        expect(run0, exitsWith(1));
        expect(
          run0.output,
          contains('Configuring app "mobile" in apps/mobile/'),
        );
        expect(run0.output, contains('stdin is not a terminal'));
      },
    );

    test(
      'warns when the app has no firebase_module.dart to import the output',
      () async {
        final run0 = await run(single());

        expect(
          run0.output,
          contains(
            'apps/mobile/lib/firebase/firebase_module.dart does not exist',
          ),
        );
      },
    );

    test('no warning when the app already has firebase_module.dart', () async {
      final ws = single(
        more: {'apps/mobile/lib/firebase/firebase_module.dart': '// module\n'},
      );

      final run0 = await run(ws);

      expect(run0.output, isNot(contains('does not exist')));
    });
  });
}
