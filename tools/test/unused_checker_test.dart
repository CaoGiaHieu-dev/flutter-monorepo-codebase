import 'package:test/test.dart';

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
}
