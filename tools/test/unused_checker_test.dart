import 'package:test/test.dart';

import 'support/fake_bin.dart';
import 'support/tool_harness.dart';

/// `tools/unused_checker` — the declared-but-unused dependency audit (CI's
/// advisory step, and blocking for a freshly generated module) and the
/// unused-file report, each run as a process against a temp workspace.
///
/// Both locate the repository from their own script location, so the
/// snapshot is copied into each workspace's `tools/unused_checker/`.
void main() {
  group('check_unused_packages', () {
    late CompiledTool tool;
    setUpAll(() async {
      tool = await CompiledTool.compile(
        'tools/unused_checker/check_unused_packages.dart',
      );
    });
    tearDownAll(() => tool.dispose());

    Future<ToolRun> check(TempWorkspace ws) => tool.run(
      const [],
      workingDirectory: ws.root,
      scriptPath: 'tools/unused_checker/check_unused_packages.dill',
    );

    TempWorkspace workspace(Map<String, String> files) => TempWorkspace.create({
      'pubspec.yaml': 'name: ws\nworkspace:\n  - pkg\n',
      'tools/.keep': '',
      ...files,
    });

    test('a declaration nothing imports is reported', () async {
      final ws = workspace({
        'pkg/pubspec.yaml': '''
name: pkg
dependencies:
  flutter:
    sdk: flutter
  used_dep: any
  unused_dep: any
''',
        'pkg/lib/pkg.dart': "import 'package:used_dep/used_dep.dart';\n",
      });

      final run = await check(ws);

      expect(run, exitsWith(2));
      expect(run.output, contains('Package: pkg'));
      expect(run.output, contains('- unused_dep'));
      expect(run.output, isNot(contains('- used_dep')));
      expect(run.output, isNot(contains('- flutter')));
    });

    test(
      'an import in test/ counts; one in another package does not',
      () async {
        final ws = workspace({
          'pkg/pubspec.yaml': 'name: pkg\ndependencies:\n  dep_a: any\n',
          'pkg/lib/pkg.dart': '',
          'pkg/test/pkg_test.dart': "import 'package:dep_a/dep_a.dart';\n",
          'other/pubspec.yaml': 'name: other\ndependencies:\n  dep_b: any\n',
          'other/lib/other.dart': '',
          'pkg/lib/uses_b.dart': "import 'package:dep_b/dep_b.dart';\n",
        });

        final run = await check(ws);

        expect(run, exitsWith(2));
        expect(run.output, contains('Package: other'));
        expect(run.output, contains('- dep_b'));
        expect(run.output, isNot(contains('- dep_a')));
      },
    );

    test('each import-less allowance holds only where it is needed', () async {
      final ws = workspace({
        // gen-l10n (l10n.yaml) and json_serializable make these legitimate.
        'l10n_pkg/pubspec.yaml': '''
name: l10n_pkg
dependencies:
  flutter_localizations:
    sdk: flutter
  intl: any
  json_annotation: any
  flutter_svg: any
dev_dependencies:
  json_serializable: any
flutter_gen:
  integrations:
    flutter_svg: true
''',
        'l10n_pkg/l10n.yaml': 'arb-dir: assets/language\n',
        'l10n_pkg/lib/l10n_pkg.dart': '',
        // The same declarations with none of those reasons.
        'plain_pkg/pubspec.yaml': '''
name: plain_pkg
dependencies:
  flutter_localizations:
    sdk: flutter
  intl: any
  json_annotation: any
  flutter_svg: any
  get_it: any
''',
        'plain_pkg/lib/plain_pkg.dart': '',
      });

      final run = await check(ws);

      expect(run, exitsWith(2));
      expect(run.output, isNot(contains('Package: l10n_pkg')));
      expect(run.output, contains('Package: plain_pkg'));
      for (final dep in [
        'flutter_localizations',
        'intl',
        'json_annotation',
        'flutter_svg',
        'get_it',
      ]) {
        expect(run.output, contains('- $dep'));
      }
    });

    test('a clean workspace exits 0', () async {
      final ws = workspace({
        'pkg/pubspec.yaml': 'name: pkg\ndependencies:\n  dep: any\n',
        'pkg/lib/pkg.dart': "export 'package:dep/dep.dart';\n",
      });

      final run = await check(ws);

      expect(run, exitsWith(0));
    });
  });

  group('check_unused_file', () {
    late CompiledTool tool;
    setUpAll(() async {
      tool = await CompiledTool.compile(
        'tools/unused_checker/check_unused_file.dart',
      );
    });
    tearDownAll(() => tool.dispose());

    Future<ToolRun> check(TempWorkspace ws) => tool.run(
      const [],
      workingDirectory: ws.root,
      scriptPath: 'tools/unused_checker/check_unused_file.dill',
    );

    /// An app using one class of a library package through its barrel.
    Map<String, String> files({String appUses = 'Used'}) => {
      'pubspec.yaml': 'name: ws\n',
      'tools/.keep': '',
      'lib_pkg/pubspec.yaml': 'name: lib_pkg\n',
      'lib_pkg/lib/lib_pkg.dart': '''
export 'src/extensions.dart';
export 'src/orphan.dart';
export 'src/used.dart';
''',
      'lib_pkg/lib/src/used.dart': '''
import 'helper.dart';

class Used {
  final helper = Helper();
}
''',
      'lib_pkg/lib/src/helper.dart': 'class Helper {}\n',
      'lib_pkg/lib/src/orphan.dart': '''
class Orphan {}

int orphanCount() => 0;
''',
      'lib_pkg/lib/src/extensions.dart': '''
extension Doubled on int {
  int get doubled => this * 2;
}
''',
      'app/pubspec.yaml': 'name: app\ndependencies:\n  lib_pkg: any\n',
      'app/lib/main.dart':
          '''
import 'package:lib_pkg/lib_pkg.dart';

void main() => $appUses();
''',
    };

    test('a file only its own barrel exports is reported', () async {
      final run = await check(TempWorkspace.create(files()));

      expect(run, exitsWith(2));
      expect(run.output, contains('lib_pkg/lib/src/orphan.dart'));
      // Named by the app, reached from it, or used by member name.
      for (final used in ['used.dart', 'helper.dart', 'extensions.dart']) {
        expect(run.output, isNot(contains('lib_pkg/lib/src/$used')));
      }
      // The barrel is the package's surface, never "unused".
      expect(run.output, isNot(contains('lib_pkg/lib/lib_pkg.dart')));
    });

    test('naming a top-level function uses its file', () async {
      final run = await check(
        TempWorkspace.create(files(appUses: 'orphanCount')),
      );

      expect(run.output, isNot(contains('lib_pkg/lib/src/orphan.dart')));
      expect(run.output, contains('lib_pkg/lib/src/used.dart'));
    });

    test('DI and routing files are entry points', () async {
      final run = await check(
        TempWorkspace.create({
          ...files(),
          'lib_pkg/lib/lib_pkg.dart': "export 'src/used.dart';\n",
          'lib_pkg/lib/src/orphan.dart': '',
          'lib_pkg/lib/di/module.dart': "import '../src/wired.dart';\n",
          'lib_pkg/lib/src/wired.dart': 'class Wired {}\n',
          'lib_pkg/lib/src/routing/home_route.dart': 'class HomeRoute {}\n',
          'lib_pkg/lib/src/extensions.dart': '',
        }),
      );

      expect(run.output, isNot(contains('wired.dart')));
      expect(run.output, isNot(contains('home_route.dart')));
    });
  });

  group('check_unused_assets', () {
    late CompiledTool tool;
    setUpAll(() async {
      tool = await CompiledTool.compile(
        'tools/unused_checker/check_unused_assets.dart',
      );
    });
    tearDownAll(() => tool.dispose());

    Future<ToolRun> check(
      TempWorkspace ws, [
      List<String> args = const [],
    ]) => tool.run(
      args,
      workingDirectory: ws.root,
      scriptPath: 'tools/unused_checker/check_unused_assets.dill',
    );

    TempWorkspace workspace({
      String assets = '    - assets/logo.png\n',
      String lib = "const logo = 'assets/logo.png';\n",
      bool withFile = true,
    }) => TempWorkspace.create({
      'pubspec.yaml': 'name: ws\n',
      'tools/.keep': '',
      'pkg/pubspec.yaml': 'name: pkg\nflutter:\n  assets:\n$assets',
      'pkg/lib/pkg.dart': lib,
      if (withFile) 'pkg/assets/logo.png': 'png',
    });

    test('an asset named by its path is used: exit 0', () async {
      final run = await check(workspace());

      expect(run, exitsWith(0));
      expect(run.output, contains('No unused assets or missing files found'));
    });

    test('an asset reached by its flutter_gen accessor is used', () async {
      final run = await check(
        workspace(lib: 'final logo = Assets.logo;\n'),
      );

      expect(run, exitsWith(0));
    });

    test('an asset nothing references exits 2 and is named', () async {
      final run = await check(workspace(lib: 'const nothing = 1;\n'));

      expect(run, exitsWith(2));
      expect(run.output, contains('Unused Assets in pkg'));
      expect(run.output, contains('pkg/assets/logo.png'));
    });

    test('a declared asset whose file is missing exits 1', () async {
      final run = await check(workspace(withFile: false));

      expect(run, exitsWith(1));
      expect(run.output, contains('Missing Files in pkg'));
      expect(run.output, contains('pkg/assets/logo.png'));
    });

    test('--help exits 0; an unknown argument exits 64', () async {
      final ws = workspace();

      final help = await check(ws, ['--help']);
      expect(help, exitsWith(0));
      expect(help.stdout, contains('check_unused_assets.dart'));

      final bad = await check(ws, ['--fix']);
      expect(bad, exitsWith(64));
      expect(bad.output, contains('Unknown argument(s): --fix'));
    });

    test('a root holding no package is a failure, not a pass', () async {
      final ws = TempWorkspace.create({
        'pubspec.yaml': 'name: ws\n',
        'tools/.keep': '',
      });

      expect(await check(ws), exitsWith(1));
    });
  });

  group('check_unused_translate', () {
    late CompiledTool tool;
    setUpAll(() async {
      tool = await CompiledTool.compile(
        'tools/unused_checker/check_unused_translate.dart',
      );
    });
    tearDownAll(() => tool.dispose());

    Future<ToolRun> check(
      TempWorkspace ws, [
      List<String> args = const [],
    ]) => tool.run(
      args,
      workingDirectory: ws.root,
      scriptPath: 'tools/unused_checker/check_unused_translate.dill',
    );

    TempWorkspace workspace({
      String arb = '{"hello": "Hello", "@hello": {}, "bye": "Bye"}',
      Map<String, String> lib = const {},
    }) => TempWorkspace.create({
      'pubspec.yaml': 'name: ws\n',
      'tools/.keep': '',
      'pkg/pubspec.yaml': 'name: pkg\n',
      'pkg/assets/language/en.arb': arb,
      'pkg/assets/language/vi.arb': arb,
      for (final entry in lib.entries) 'pkg/lib/${entry.key}': entry.value,
    });

    test('every key read through context.l10n is clean: exit 0', () async {
      final run = await check(
        workspace(
          lib: {
            'page.dart': 'void f(context) { context.l10nPkg.hello; context.l10nPkg.bye; }\n',
          },
        ),
      );

      expect(run, exitsWith(0));
      expect(run.output, contains('No unused translation keys found'));
    });

    test(
      'a key no code reads exits 2 and is named; @metadata is not a key',
      () async {
        final run = await check(
          workspace(
            lib: {'page.dart': 'void f(context) => context.l10nPkg.hello;\n'},
          ),
        );

        expect(run, exitsWith(2));
        expect(run.output, contains('Package: pkg'));
        expect(run.output, contains('- bye'));
        expect(run.output, isNot(contains('- hello')));
        expect(run.output, isNot(contains('@hello')));
      },
    );

    test(
      'a key read as a bare getter inside `extension on AppLocalizations` '
      'is used; the same word elsewhere is not',
      () async {
        final run = await check(
          workspace(
            lib: {
              'failure.dart': '''
extension FailureMessageExtension on AppLocalizations {
  String message(int code) {
    return switch (code) {
      1 => hello,
      _ => 'x',
    };
  }
}
''',
              // `bye` is only a word in a plain class: not a read.
              'other.dart': 'class Other { final bye = 1; }\n',
            },
          ),
        );

        expect(run, exitsWith(2));
        expect(run.output, contains('- bye'));
        expect(run.output, isNot(contains('- hello')));
      },
    );

    test('--help exits 0; an unknown argument exits 64', () async {
      final ws = workspace();

      expect(await check(ws, ['--help']), exitsWith(0));
      expect(await check(ws, ['--nope']), exitsWith(64));
    });

    test('a workspace without any ARB file passes with a notice', () async {
      final ws = TempWorkspace.create({
        'pubspec.yaml': 'name: ws\n',
        'tools/.keep': '',
        'pkg/pubspec.yaml': 'name: pkg\n',
        'pkg/lib/pkg.dart': '',
      });

      final run = await check(ws);

      expect(run, exitsWith(0));
      expect(run.output, contains('No translation keys found'));
    });
  });

  group('check_script', () {
    late CompiledTool tool;
    setUpAll(() async {
      tool = await CompiledTool.compile(
        'tools/unused_checker/check_script.dart',
      );
    });
    tearDownAll(() => tool.dispose());

    /// A fake `dart` standing in for the four checkers: the exit code of
    /// each is scripted by the name of the script it was asked to run.
    FakeBin fakeDart({
      int assets = 0,
      int translate = 0,
      int file = 0,
      int packages = 0,
    }) => FakeBin.create({
      'dart':
          '''
case "\$*" in
  *check_unused_assets*) exit $assets ;;
  *check_unused_translate*) exit $translate ;;
  *check_unused_file*) exit $file ;;
  *check_unused_packages*) exit $packages ;;
esac
exit 99
''',
    });

    Future<ToolRun> check(FakeBin bin, [List<String> args = const []]) {
      final ws = TempWorkspace.create({
        'pubspec.yaml': 'name: ws\n',
        'tools/.keep': '',
      });
      return tool.run(
        args,
        workingDirectory: ws.root,
        scriptPath: 'tools/unused_checker/check_script.dill',
        environment: bin.environment,
      );
    }

    final skip = skipWithoutPosixShell();

    test('runs the four checks in order; all clean exits 0', () async {
      final bin = fakeDart();

      final run = await check(bin);

      expect(run, exitsWith(0));
      expect(run.output, contains('All checks passed! Your project is clean.'));
      expect(bin.argsOf('dart'), [
        'run tools/unused_checker/check_unused_assets.dart',
        'run tools/unused_checker/check_unused_translate.dart',
        'run tools/unused_checker/check_unused_file.dart',
        'run tools/unused_checker/check_unused_packages.dart',
      ]);
    }, skip: skip);

    test('findings (exit 2) are warnings: the run still exits 0', () async {
      final run = await check(fakeDart(translate: 2, file: 2));

      expect(run, exitsWith(0));
      expect(run.output, contains('Warnings Found'));
      expect(run.output, contains('some have warnings'));
    }, skip: skip);

    test(
      'a check that fails (any other non-zero exit) exits 1, after the rest ran',
      () async {
        final bin = fakeDart(assets: 1, packages: 2);

        final run = await check(bin);

        expect(run, exitsWith(1));
        expect(run.output, contains('Failed Checks'));
        expect(run.output, contains('Some checks failed'));
        // It keeps going: all four were run.
        expect(bin.argsOf('dart'), hasLength(4));
      },
      skip: skip,
    );

    test('a check that cannot run (crash code) is a failure too', () async {
      final run = await check(fakeDart(file: 254));

      expect(run, exitsWith(1));
    }, skip: skip);

    test('--help exits 0; an unknown argument exits 64', () async {
      final bin = fakeDart();

      final help = await check(bin, ['--help']);
      expect(help, exitsWith(0));
      expect(help.stdout, contains('check_script.dart'));

      final bad = await check(bin, ['--all']);
      expect(bad, exitsWith(64));
      expect(bad.output, contains('Unknown argument(s): --all'));
      expect(bin.calls, isEmpty);
    }, skip: skip);
  });
}
