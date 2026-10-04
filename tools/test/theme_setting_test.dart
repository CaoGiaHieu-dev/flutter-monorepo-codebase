import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/fake_bin.dart';
import 'support/tool_harness.dart';

/// `tools/theme_generator/theme_setting.dart` — splash screen and launcher
/// icons for one app.
///
/// The generators (`flutter_native_splash`, `icons_launcher`) are replaced by
/// a fake `dart` on `PATH`, so what is asserted is the tool's own job: the
/// preflight checks, which commands it runs and where, copying the configs
/// into the app, and — when a generator fails — restoring the platform
/// directories and removing the copied configs.
void main() {
  late CompiledTool tool;
  setUpAll(() async {
    tool = await CompiledTool.compile(
      'tools/theme_generator/theme_setting.dart',
    );
  });
  tearDownAll(() => tool.dispose());

  const pubspecWithGenerators = '''
name: mobile
dev_dependencies:
  flutter_native_splash: ^2.4.0
  icons_launcher: ^3.0.0
''';

  /// A workspace holding one fully prepared app.
  TempWorkspace ready({Map<String, String> more = const {}}) =>
      TempWorkspace.create({
        'pubspec.yaml': 'name: ws\nworkspace:\n  - apps/mobile\n',
        'apps/mobile/app_manifest.yaml': 'app:\n  id: mobile\n',
        'apps/mobile/pubspec.yaml': pubspecWithGenerators,
        'apps/mobile/android/app/src/main/res/launcher.txt': 'old android icon',
        'apps/mobile/ios/Runner/icon.txt': 'old ios icon',
        'flutter_native_splash-dev.yaml': 'flutter_native_splash: {}\n',
        'flutter_native_splash-prod.yaml': 'flutter_native_splash: {}\n',
        'icons_launcher-dev.yaml': 'icons_launcher: {}\n',
        ...more,
      });

  Future<ToolRun> run(
    TempWorkspace ws, {
    List<String> args = const [],
    FakeBin? bin,
  }) => tool.run(
    args,
    workingDirectory: ws.root,
    environment: bin?.environment,
  );

  group('arguments', () {
    test('--help prints the usage and exits 0', () async {
      final run0 = await run(ready(), args: ['--help']);

      expect(run0, exitsWith(0));
      expect(
        run0.stdout,
        contains(
          'Usage: dart tools/theme_generator/theme_setting.dart [--app <id>]',
        ),
      );
      expect(run0.stdout, contains('flutter_native_splash-<flavor>.yaml'));
      expect(run0.stdout, contains('restored'));
    });

    test('-h is the same as --help', () async {
      final run0 = await run(ready(), args: ['-h']);

      expect(run0, exitsWith(0));
      expect(run0.stdout, contains('Usage:'));
    });

    test('an unknown argument exits 64 with the usage', () async {
      final run0 = await run(ready(), args: ['--flavor', 'dev']);

      expect(run0, exitsWith(64));
      expect(run0.output, contains('Unknown argument: --flavor'));
      expect(run0.stderr, contains('Usage:'));
    });

    test('--app without an id exits 64', () async {
      final run0 = await run(ready(), args: ['--app']);

      expect(run0, exitsWith(64));
      expect(run0.output, contains('--app needs an id'));
    });

    test('--app with an unknown id exits 64', () async {
      final run0 = await run(ready(), args: ['--app', 'ghost']);

      expect(run0, exitsWith(64));
      expect(run0.output, contains('No app with id "ghost"'));
    });

    test('several apps without --app exit 64', () async {
      final ws = ready(
        more: {'apps/admin/app_manifest.yaml': 'app:\n  id: admin\n'},
      );

      final run0 = await run(ws);

      expect(run0, exitsWith(64));
      expect(run0.output, contains('2 apps found; say which one with --app'));
    });

    test('a workspace without an app exits 1', () async {
      final ws = TempWorkspace.create({'pubspec.yaml': 'name: ws\n'});

      final run0 = await run(ws);

      expect(run0, exitsWith(1));
      expect(run0.output, contains('No app found'));
    });
  });

  group('preflight', () {
    test('an app without android/ and ios/ exits 1 naming both', () async {
      final ws = TempWorkspace.create({
        'pubspec.yaml': 'name: ws\n',
        'apps/mobile/app_manifest.yaml': 'app:\n  id: mobile\n',
        'apps/mobile/pubspec.yaml': pubspecWithGenerators,
        'icons_launcher-dev.yaml': 'icons_launcher: {}\n',
      });

      final run0 = await run(ws);

      expect(run0, exitsWith(1));
      expect(
        run0.output,
        contains('Cannot generate splash and icons for "mobile"'),
      );
      expect(run0.output, contains('apps/mobile/android/ does not exist'));
      expect(run0.output, contains('apps/mobile/ios/ does not exist'));
    });

    test('an app that does not declare the generators exits 1', () async {
      final ws = ready(
        more: {
          'apps/mobile/pubspec.yaml':
              'name: mobile\ndev_dependencies:\n  test: any\n',
        },
      );

      final run0 = await run(ws);

      expect(run0, exitsWith(1));
      expect(run0.output, contains('does not declare flutter_native_splash'));
      expect(run0.output, contains('does not declare icons_launcher'));
    });

    test('no config files at the repository root exits 1', () async {
      final ws = ready();
      File(p.join(ws.root, 'flutter_native_splash-dev.yaml')).deleteSync();
      File(p.join(ws.root, 'flutter_native_splash-prod.yaml')).deleteSync();
      File(p.join(ws.root, 'icons_launcher-dev.yaml')).deleteSync();

      final run0 = await run(ws);

      expect(run0, exitsWith(1));
      expect(
        run0.output,
        contains('No flutter_native_splash-*.yaml / icons_launcher-*.yaml'),
      );
    });

    test('a failed preflight runs no generator and writes nothing', () async {
      final ws = ready(
        more: {'apps/mobile/pubspec.yaml': 'name: mobile\n'},
      );
      final bin = FakeBin.create({'dart': 'exit 0'});

      final run0 = await run(ws, bin: bin);

      expect(run0, exitsWith(1));
      expect(bin.calls, isEmpty);
      expect(ws.exists('apps/mobile/icons_launcher-dev.yaml'), isFalse);
    });
  });

  group('generation', () {
    test(
      'runs both generators in the app with the three flavors and cleans up',
      () async {
        final ws = ready();
        // The fake sees the copied configs, as the real generators must.
        final bin = FakeBin.create({
          'dart': 'ls >> "\$FAKE_LS"',
        });
        final lsLog = p.join(p.dirname(bin.dir), 'ls.log');

        final run0 = await tool.run(
          const [],
          workingDirectory: ws.root,
          environment: {...bin.environment, 'FAKE_LS': lsLog},
        );

        expect(run0, exitsWith(0));
        expect(run0.output, contains('Splash & Icon generation complete'));
        expect(bin.calls, hasLength(2));
        expect(
          bin.argsOf('dart'),
          [
            'run flutter_native_splash:create --flavors dev,staging,prod',
            'run icons_launcher:create --flavors dev,staging,prod',
          ],
        );
        // Both ran inside the app, never at the root.
        expect(
          bin.calls.every((c) => c.split(' ')[1].endsWith('/apps/mobile')),
          isTrue,
        );
        final seen = File(lsLog).readAsStringSync();
        expect(seen, contains('flutter_native_splash-dev.yaml'));
        expect(seen, contains('flutter_native_splash-prod.yaml'));
        expect(seen, contains('icons_launcher-dev.yaml'));
        // Nothing is left behind in the app, the root's configs are kept.
        expect(
          ws.exists('apps/mobile/flutter_native_splash-dev.yaml'),
          isFalse,
        );
        expect(ws.exists('apps/mobile/icons_launcher-dev.yaml'), isFalse);
        expect(ws.exists('flutter_native_splash-dev.yaml'), isTrue);
      },
      skip: skipWithoutPosixShell(),
    );

    test(
      '--app picks one of several apps',
      () async {
        final ws = ready(
          more: {
            'apps/admin/app_manifest.yaml': 'app:\n  id: admin\n',
            'apps/admin/pubspec.yaml': pubspecWithGenerators,
            'apps/admin/android/.keep': '',
            'apps/admin/ios/.keep': '',
          },
        );
        final bin = FakeBin.create({'dart': 'exit 0'});

        final run0 = await run(ws, args: ['--app', 'admin'], bin: bin);

        expect(run0, exitsWith(0));
        expect(
          bin.calls.every((c) => c.split(' ')[1].endsWith('/apps/admin')),
          isTrue,
        );
      },
      skip: skipWithoutPosixShell(),
    );

    test(
      'a failing generator exits 1, restores android/ ios/ web/ and removes '
      'the copied configs',
      () async {
        final ws = ready(
          more: {'apps/mobile/web/index.html': '<html>original</html>'},
        );
        // The first generator rewrites an existing file, adds a file and a
        // directory, then fails.
        final bin = FakeBin.create({
          'dart': '''
echo "changed" > android/app/src/main/res/launcher.txt
echo "new" > ios/Runner/generated_icon.txt
mkdir -p android/app/src/dev/res
echo "new" > android/app/src/dev/res/ic.txt
rm web/index.html
exit 5
''',
        });

        final run0 = await run(ws, bin: bin);

        expect(run0, exitsWith(1));
        expect(run0.output, contains('failed with exit code 5'));
        expect(run0.output, contains('Restoring apps/mobile/android/'));
        expect(
          ws.read('apps/mobile/android/app/src/main/res/launcher.txt'),
          'old android icon',
        );
        expect(ws.read('apps/mobile/ios/Runner/icon.txt'), 'old ios icon');
        expect(ws.read('apps/mobile/web/index.html'), '<html>original</html>');
        expect(ws.exists('apps/mobile/ios/Runner/generated_icon.txt'), isFalse);
        expect(ws.exists('apps/mobile/android/app/src/dev'), isFalse);
        expect(
          ws.exists('apps/mobile/flutter_native_splash-dev.yaml'),
          isFalse,
        );
        expect(ws.exists('apps/mobile/icons_launcher-dev.yaml'), isFalse);
        // The second generator never ran after the first failed.
        expect(bin.calls, hasLength(1));
      },
      skip: skipWithoutPosixShell(),
    );
  });
}
