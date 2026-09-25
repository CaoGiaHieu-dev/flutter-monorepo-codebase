import 'package:test/test.dart';

import 'support/tool_harness.dart';

/// `tools/barrel_generator/generate.dart` — run after every file add, rename
/// or delete, and by `configure.dart` for every package.
void main() {
  late CompiledTool tool;

  setUpAll(() async {
    tool = await CompiledTool.compile('tools/barrel_generator/generate.dart');
  });
  tearDownAll(() => tool.dispose());

  TempWorkspace package() => TempWorkspace.create({
    'pkg/pubspec.yaml': 'name: demo_pkg\n',
    'pkg/lib/src/a.dart': 'class A {}\n',
    'pkg/lib/src/a.g.dart': '// GENERATED CODE\n',
    'pkg/lib/src/part_file.dart': "part of 'a.dart';\n",
    // `web/` is excluded only as a platform folder *outside* lib/ — a
    // feature directory named web inside lib/ is ordinary source.
    'pkg/lib/src/web/web_view.dart': 'class WebView {}\n',
    'pkg/lib/src/gen/assets.gen.dart': 'class Assets {}\n',
    'pkg/lib/gen/flutter_gen.dart': 'class FlutterGen {}\n',
    'pkg/lib/di/module.dart': 'class Module {}\n',
    'pkg/web/index.dart': 'void main() {}\n',
  });

  test('one barrel exports every library file of the package', () async {
    final ws = package();
    final run = await tool.run(const [
      'pkg/lib/',
    ], workingDirectory: ws.root);
    expect(run, exitsWith(0));
    expect(run.output, contains('[SUCCESS] Barrel generated: 4 exports.'));

    final barrel = ws.read('pkg/lib/demo_pkg.dart');
    expect(barrel, contains("export 'di/module.dart';"));
    expect(barrel, contains("export 'src/a.dart';"));
    expect(barrel, contains("export 'src/web/web_view.dart';"));
    // Generated files present on disk under lib/src/gen are exported — the
    // reason the generator must run after gen-l10n / build_runner.
    expect(barrel, contains("export 'src/gen/assets.gen.dart';"));
    // `.g.dart` parts, `part of` files and lib/gen are not.
    expect(barrel, isNot(contains('a.g.dart')));
    expect(barrel, isNot(contains('part_file.dart')));
    expect(barrel, isNot(contains('flutter_gen.dart')));
    // No directory barrels, and the platform web/ beside lib/ is untouched.
    expect(ws.exists('pkg/lib/src/src.dart'), isFalse);
    expect(ws.exists('pkg/lib/src/web/web.dart'), isFalse);
    expect(ws.exists('pkg/web/web.dart'), isFalse);
  });

  test('directory barrels from the old layout are removed', () async {
    final ws = package();
    ws.write({
      'pkg/lib/src/src.dart':
          '// Auto-generated exports, do not edit manually.\n'
          "export 'a.dart';\n"
          "export 'web/web.dart';\n",
      'pkg/lib/src/web/web.dart':
          '// Auto-generated exports, do not edit manually.\n'
          "export 'web_view.dart';\n",
      'pkg/lib/src/only/only.dart':
          '// Auto-generated exports, do not edit manually.\n',
      // A directory barrel that also holds code keeps the code.
      'pkg/lib/src/typedefs.dart':
          "import 'dart:async';\n\n"
          '// Auto-generated exports, do not edit manually.\n'
          "export 'a.dart';\n\n"
          'typedef Kept = FutureOr<void>;\n',
    });
    expect(
      await tool.run(const ['pkg/lib'], workingDirectory: ws.root),
      exitsWith(0),
    );
    expect(ws.exists('pkg/lib/src/src.dart'), isFalse);
    expect(ws.exists('pkg/lib/src/web/web.dart'), isFalse);
    // Left empty, the directory goes too.
    expect(ws.exists('pkg/lib/src/only'), isFalse);
    final kept = ws.read('pkg/lib/src/typedefs.dart');
    expect(kept, contains('typedef Kept = FutureOr<void>;'));
    expect(kept, isNot(contains('export')));
    expect(
      ws.read('pkg/lib/demo_pkg.dart'),
      contains("export 'src/typedefs.dart';"),
    );
  });

  test('hand-written exports are replaced, the doc comment is kept', () async {
    final ws = package();
    ws.write({
      'pkg/lib/demo_pkg.dart':
          '/// The demo package.\n'
          'library;\n\n'
          "export 'stale.dart';\n",
    });
    expect(
      await tool.run(const ['pkg/lib'], workingDirectory: ws.root),
      exitsWith(0),
    );
    final barrel = ws.read('pkg/lib/demo_pkg.dart');
    expect(barrel, startsWith('/// The demo package.\nlibrary;\n'));
    expect(barrel, isNot(contains('stale.dart')));
    expect(barrel, contains("export 'src/a.dart';"));
  });

  test('a path that does not exist exits 64', () async {
    final ws = package();
    final run = await tool.run(const ['nope/lib'], workingDirectory: ws.root);
    expect(run, exitsWith(64));
    expect(run.output, contains('does not exist'));
  });

  test('a directory that is not a package lib/ exits 64', () async {
    final ws = package();
    final run = await tool.run(const [
      'pkg/lib/src',
    ], workingDirectory: ws.root);
    expect(run, exitsWith(64));
    expect(run.output, contains('is not a package lib/ directory'));
    expect(ws.exists('pkg/lib/src/src.dart'), isFalse);
  });
}
