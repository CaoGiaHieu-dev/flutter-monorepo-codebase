import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
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

  /// A fake `flutter create`: writes `<target>/web/index.html`,
  /// `<target>/linux/CMakeLists.txt` and the files the real one writes beside
  /// the platforms. A fake `flutter pub get` (`--offline` alike): writes what
  /// the real one adds to a Linux runner in the working directory — the file
  /// a `--no-pub` build of it includes — or exits 69 while the workspace
  /// holds `.pub_fails` (no network, say).
  const fakeFlutter = r'''
if [ "$1" = "pub" ]; then
  if [ -f ../../.pub_fails ]; then
    echo 'Failed to update packages.' >&2
    exit 69
  fi
  if [ -d linux ]; then
    mkdir -p linux/flutter
    echo '# plugins' > linux/flutter/generated_plugins.cmake
  fi
  exit 0
fi
for a; do last="$a"; done
mkdir -p "$last/web" "$last/linux" "$last/test"
echo '<html></html>' > "$last/web/index.html"
echo 'include(flutter/generated_plugins.cmake)' > "$last/linux/CMakeLists.txt"
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
  TempWorkspace workspace({
    String scaffold = '  web: { runner: scaffold }\n',
  }) => TempWorkspace.create(
    demoWorkspaceFiles(
      manifest: demoManifest(
        appBlock: 'app:\n  id: demo\n  name: Demo App\n  org: com.acme\n',
        platforms:
            'platforms:\n'
            '  android: { runner: committed }\n'
            '$scaffold',
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
      final flutterCalls = bin.argsOf('flutter');
      expect(flutterCalls, hasLength(2));
      expect(flutterCalls.last, 'pub get');
      final create = flutterCalls.first.split(' ');
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
      // The web asset step ran: the worker was compiled from the repo root
      // into a temporary directory …
      final compile = bin.argsOf('dart').single.split(' ');
      expect(compile.take(4), ['compile', 'js', '-O4', '-o']);
      expect(compile[4], endsWith('/drift_worker.js'));
      expect(compile[4], isNot(startsWith(ws.root)));
      expect(compile.last, kDriftWorkerSource);
      expect(bin.calls.last.split(' ')[1], ws.root);
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

  test(
    'a second run with nothing changed writes nothing — drift_worker.js '
    'and sqlite3.wasm included — and says the runner is up to date',
    () async {
      final ws = workspace();
      // A wasm already in the cache, and the hash table naming it.
      const wasm = [1, 2, 3, 4];
      File(
        p.join(ws.root, 'pub/sqlite3-9.9.9/$kSqliteAssetHashes'),
      ).writeAsStringSync(
        "const String? releaseTag = 'sqlite3-9.9.9';\n"
        "const assetNameToSha256Hash = {'sqlite3.wasm': "
        "'${sha256.convert(wasm)}'};\n",
      );
      File(
          p.join(
            ws.root,
            '.cache/flutter_monorepo/sqlite3/sqlite3-9.9.9/sqlite3.wasm',
          ),
        )
        ..createSync(recursive: true)
        ..writeAsBytesSync(wasm);
      final bin = FakeBin.create({'flutter': fakeFlutter, 'dart': fakeDart});
      final first = await runners(ws, bin);
      expect(first, exitsWith(0));
      expect(first.output, contains('wrote apps/demo/web/drift_worker.js'));
      expect(first.output, contains('wrote apps/demo/web/sqlite3.wasm'));
      final then = DateTime(2001);
      final written = [
        for (final rel in ['web/drift_worker.js', 'web/sqlite3.wasm'])
          File(p.join(ws.root, 'apps/demo', rel))..setLastModifiedSync(then),
      ];

      final second = await runners(ws, bin);

      expect(second, exitsWith(0));
      for (final file in written) {
        expect(file.lastModifiedSync(), then, reason: file.path);
      }
      expect(second.output, isNot(contains('wrote ')));
      expect(
        second.output,
        contains('apps/demo: up to date (web) — nothing written'),
      );
      // One create and one pub get, both from the first run.
      expect(bin.argsOf('flutter'), hasLength(2));
    },
    skip: skipWithoutPosixShell(),
  );

  test(
    'a new Linux runner gets its plugin files from pub get in the app, so a '
    '--no-pub build finds them; --offline runs `flutter pub get --offline`',
    () async {
      final ws = workspace(scaffold: '  linux: { runner: scaffold }\n');
      final bin = FakeBin.create({'flutter': fakeFlutter, 'dart': fakeDart});

      final result = await runners(ws, bin);

      expect(result, exitsWith(0));
      expect(ws.exists('apps/demo/linux/CMakeLists.txt'), isTrue);
      expect(
        ws.exists('apps/demo/linux/flutter/generated_plugins.cmake'),
        isTrue,
      );
      final pubGet = bin.calls.singleWhere((c) => c.endsWith(' pub get'));
      expect(pubGet.split(' ')[1], p.join(ws.root, 'apps', 'demo'));

      final again = await runners(ws, bin);
      expect(again, exitsWith(0));
      expect(again.output, contains('apps/demo: up to date (linux)'));
      expect(bin.calls.where((c) => c.endsWith(' pub get')), hasLength(1));

      final offline = await runners(ws, bin, ['--force', '--offline']);
      expect(offline, exitsWith(0));
      expect(ws.exists('apps/demo/linux/CMakeLists.txt'), isTrue);
      expect(
        ws.exists('apps/demo/linux/flutter/generated_plugins.cmake'),
        isTrue,
      );
      expect(bin.calls.where((c) => c.endsWith(' pub get')), hasLength(1));
      expect(
        bin.calls.where((c) => c.endsWith(' pub get --offline')),
        hasLength(1),
      );
    },
    skip: skipWithoutPosixShell(),
  );

  test(
    'a pub get that failed is tried again by the next run, which is never '
    '`up to date` until the plugin files are there',
    () async {
      final ws = workspace(scaffold: '  linux: { runner: scaffold }\n');
      final bin = FakeBin.create({'flutter': fakeFlutter, 'dart': fakeDart});
      final fails = File(p.join(ws.root, '.pub_fails'))..createSync();

      final first = await runners(ws, bin, ['--app', 'demo']);
      expect(first, exitsWith(1));
      expect(first.output, contains('`flutter pub get` failed (exit 69)'));
      expect(ws.exists('apps/demo/linux/CMakeLists.txt'), isTrue);

      final second = await runners(ws, bin, ['--app', 'demo']);
      expect(second, exitsWith(1));
      expect(second.output, isNot(contains('up to date')));
      expect(second.output, isNot(contains('Every generated runner')));

      fails.deleteSync();
      final third = await runners(ws, bin, ['--app', 'demo']);
      expect(third, exitsWith(0));
      expect(third.output, isNot(contains('up to date')));
      expect(
        ws.exists('apps/demo/linux/flutter/generated_plugins.cmake'),
        isTrue,
      );
      expect(bin.calls.where((c) => c.endsWith(' pub get')), hasLength(3));
      // One create, from the first run.
      expect(bin.calls.where((c) => c.contains(' create ')), hasLength(1));

      final fourth = await runners(ws, bin, ['--app', 'demo']);
      expect(fourth, exitsWith(0));
      expect(fourth.output, contains('apps/demo: up to date (linux)'));
      expect(bin.calls.where((c) => c.endsWith(' pub get')), hasLength(3));
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
