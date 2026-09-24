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
    'pkg/web/index.dart': 'void main() {}\n',
  });

  test('a trailing slash still names the package barrel', () async {
    final ws = package();
    final run = await tool.run(const [
      'pkg/lib/',
    ], workingDirectory: ws.root);
    expect(run, exitsWith(0));
    expect(run.output, contains('[SUCCESS] Barrel files generated.'));

    // `lib/` is recognised as the package root despite the slash, so the
    // barrel is named from pubspec.yaml rather than skipped.
    expect(ws.exists('pkg/lib/demo_pkg.dart'), isTrue);
    expect(
      ws.read('pkg/lib/demo_pkg.dart'),
      contains("export 'src/src.dart';"),
    );
  });

  test('a nested web/ directory inside lib/ is exported', () async {
    final ws = package();
    expect(
      await tool.run(const ['pkg/lib'], workingDirectory: ws.root),
      exitsWith(0),
    );

    expect(
      ws.read('pkg/lib/src/web/web.dart'),
      contains("export 'web_view.dart';"),
    );
    final src = ws.read('pkg/lib/src/src.dart');
    expect(src, contains("export 'a.dart';"));
    expect(src, contains("export 'web/web.dart';"));
    // Generated `.g.dart` parts and `part of` files are never exported.
    expect(src, isNot(contains('a.g.dart')));
    expect(src, isNot(contains('part_file.dart')));
    // Generated files present on disk under lib/src/gen are — the reason
    // the generator must run after gen-l10n / build_runner.
    expect(src, contains("export 'gen/gen.dart';"));
    // The platform web/ folder beside lib/ is left alone.
    expect(ws.exists('pkg/web/web.dart'), isFalse);
  });

  test('hand-written exports are replaced, other code is kept', () async {
    final ws = package();
    ws.write({
      'pkg/lib/src/src.dart':
          "import 'dart:async';\n\n"
          "export 'stale.dart';\n\n"
          'typedef Kept = FutureOr<void>;\n',
    });
    expect(
      await tool.run(const ['pkg/lib'], workingDirectory: ws.root),
      exitsWith(0),
    );
    final src = ws.read('pkg/lib/src/src.dart');
    expect(src, isNot(contains('stale.dart')));
    expect(src, contains('typedef Kept = FutureOr<void>;'));
    expect(src, contains("export 'a.dart';"));
  });

  test('a path that does not exist exits 64', () async {
    final ws = package();
    final run = await tool.run(const ['nope/lib'], workingDirectory: ws.root);
    expect(run, exitsWith(64));
    expect(run.output, contains('does not exist'));
  });
}
