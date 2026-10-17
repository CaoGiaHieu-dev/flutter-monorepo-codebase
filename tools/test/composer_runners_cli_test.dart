import 'package:test/test.dart';

import '../composer/src/runners.dart';
import 'support/composer_fixture.dart';
import 'support/fake_bin.dart';
import 'support/tool_harness.dart';

/// `dart tools/composer/composer.dart runners`, run as a process: what
/// `composer_runners_test.dart` cannot see, because it builds each
/// `RunnerApp` by hand — how the command reads the apps (the pubspec name,
/// `app.org`, whether core_database is linked), its exit codes and its
/// arguments.
///
/// `flutter` and `dart` are shell fakes on `PATH`; the download goes through
/// a proxy nobody listens on, so it is the offline path.
void main() {
  late CompiledTool tool;

  setUpAll(() async {
    tool = await CompiledTool.compile('tools/composer/composer.dart');
  });
  tearDownAll(() => tool.dispose());

  /// A fake `flutter create`: writes `<target>/web/index.html` and the files
  /// the real one writes beside the platforms.
  const fakeFlutter = r'''
for a; do last="$a"; done
mkdir -p "$last/web" "$last/test"
echo '<html></html>' > "$last/web/index.html"
echo 'MyApp();' > "$last/test/widget_test.dart"
''';

  /// A fake `dart compile js … -o <out> …`: writes `<out>`.
  const fakeDart = r'''
while [ $# -gt 0 ]; do
  if [ "$1" = "-o" ]; then out="$2"; fi
  shift
done
mkdir -p "$(dirname "$out")"
echo '// worker' > "$out"
''';

  /// The demo app declared for the web, with core_database linked through
  /// core_common, and the resolved sqlite3 with its hash table.
  TempWorkspace workspace() => TempWorkspace.create(
    demoWorkspaceFiles(
      manifest: demoManifest(
        appBlock: 'app:\n  id: demo\n  name: Demo App\n  org: com.acme\n',
        platforms:
            'platforms:\n'
            '  android: { runner: committed }\n'
            '  web: { runner: scaffold }\n',
      ),
      extra: {
        'platform/foundation/common/pubspec.yaml':
            'name: core_common\n'
            'dependencies:\n'
            '  core_database:\n'
            '    path: ../../infra/database\n',
        'platform/infra/database/pubspec.yaml': 'name: core_database\n',
        kDriftWorkerSource: 'void main() {}\n',
        '.dart_tool/package_config.json':
            '{"configVersion": 2, "packages": [{"name": "sqlite3", '
            '"rootUri": "../pub/sqlite3-9.9.9", "packageUri": "lib/"}]}',
        'pub/sqlite3-9.9.9/pubspec.yaml': 'name: sqlite3\nversion: 9.9.9\n',
        'pub/sqlite3-9.9.9/$kSqliteAssetHashes':
            "const String? releaseTag = 'sqlite3-9.9.9';\n"
            "const assetNameToSha256Hash = {'sqlite3.wasm': '${'a' * 64}'};\n",
      },
    ),
  );

  Future<ToolRun> runners(
    TempWorkspace ws,
    FakeBin bin, [
    List<String> args = const [],
  ]) => tool.run(
    ['runners', ...args],
    workingDirectory: ws.root,
    environment: {
      ...bin.environment,
      // Nothing listens there: the download fails as offline.
      'https_proxy': 'http://127.0.0.1:9',
      'HTTPS_PROXY': 'http://127.0.0.1:9',
      'no_proxy': '',
      'NO_PROXY': '',
      'XDG_CACHE_HOME': '${ws.root}/.cache',
    },
  );

  test(
    'generates the web runner with the pubspec name and app.org, and '
    'adds the database assets of an app that links core_database',
    () async {
      final ws = workspace();
      final bin = FakeBin.create({'flutter': fakeFlutter, 'dart': fakeDart});

      final result = await runners(ws, bin);

      expect(result, exitsWith(0));
      final create = bin.argsOf('flutter').single.split(' ');
      expect(
        create.take(7),
        [
          'create',
          '--no-pub',
          '--platforms=web',
          '--org',
          'com.acme',
          '--project-name',
          'demo_app',
        ],
      );
      expect(create.last, endsWith('/demo_app'));
      expect(create.last, isNot(startsWith(ws.root)));
      expect(ws.exists('apps/demo/web/index.html'), isTrue);
      expect(ws.exists('apps/demo/test/widget_test.dart'), isFalse);
      // The web asset step ran: the worker was compiled from the repo root …
      expect(bin.argsOf('dart'), [
        'compile js -O4 -o apps/demo/web/drift_worker.js '
            '$kDriftWorkerSource',
      ]);
      expect(ws.exists('apps/demo/web/drift_worker.js'), isTrue);
      // … and the wasm download was tried, and is the offline warning.
      expect(
        result.output,
        contains(
          'apps/demo/web: web database assets missing',
        ),
      );
      expect(ws.exists('apps/demo/web/sqlite3.wasm'), isFalse);
    },
    skip: skipWithoutPosixShell(),
  );

  test('a committed runner is never written', () async {
    final ws = workspace();
    final bin = FakeBin.create({'flutter': fakeFlutter, 'dart': fakeDart});

    final result = await runners(ws, bin, ['--platform', 'android']);

    expect(result, exitsWith(1));
    expect(
      result.output,
      contains(
        'apps/demo/android/ is committed — composer never writes into it',
      ),
    );
    expect(bin.argsOf('flutter'), isEmpty);
  }, skip: skipWithoutPosixShell());

  test('an unknown app is exit 1, an unknown flag exit 64', () async {
    final ws = workspace();
    final bin = FakeBin.create({'flutter': fakeFlutter, 'dart': fakeDart});

    final unknownApp = await runners(ws, bin, ['--app', 'nope']);
    expect(unknownApp, exitsWith(1));
    expect(
      unknownApp.output,
      contains('No app matches `--app nope`. Known: demo.'),
    );

    final unknownFlag = await runners(ws, bin, ['--frce']);
    expect(unknownFlag, exitsWith(64));
    expect(
      unknownFlag.output,
      contains('Unknown argument `--frce` for `runners`.'),
    );
    expect(bin.calls, isEmpty);
  }, skip: skipWithoutPosixShell());
}
