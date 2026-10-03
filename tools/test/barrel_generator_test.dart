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

  group('a hand-added export never survives, however it is written', () {
    Future<String> barrelAfter(String barrelSource) async {
      final ws = package();
      ws.write({'pkg/lib/demo_pkg.dart': barrelSource});
      expect(
        await tool.run(const ['pkg/lib'], workingDirectory: ws.root),
        exitsWith(0),
      );
      return ws.read('pkg/lib/demo_pkg.dart');
    }

    test('a double-quoted export after `library;`', () async {
      final barrel = await barrelAfter(
        '/// Doc.\nlibrary;\n\n'
        'export "package:flutter/material.dart" show Colors;\n',
      );
      expect(barrel, isNot(contains('package:flutter')));
      expect(barrel, startsWith('/// Doc.\nlibrary;\n'));
      expect(barrel, contains("export 'src/a.dart';"));
    });

    test('no space after export', () async {
      final barrel = await barrelAfter("library;\nexport'x.dart';\n");
      expect(barrel, isNot(contains('x.dart')));
    });

    test(
      'a show clause that wraps over lines, with its continuation lines',
      () async {
        final barrel = await barrelAfter(
          'library;\n'
          "export 'package:flutter/material.dart'\n"
          '    show\n'
          '        Colors,\n'
          '        Icons;\n'
          "export 'package:meta/meta.dart'\n    hide Immutable;\n",
        );
        expect(barrel, isNot(contains('Colors')));
        expect(barrel, isNot(contains('Icons')));
        expect(barrel, isNot(contains('Immutable')));
        expect(barrel, isNot(contains('package:meta')));
        expect(barrel, contains("export 'src/a.dart';"));
      },
    );

    test('a conditional export, and an export after an import and a comment', () async {
      final barrel = await barrelAfter(
        "import 'dart:async';\n"
        "export 'stub.dart' if (dart.library.io) 'io.dart';\n"
        '// export \'in_a_comment.dart\';\n'
        "export 'late.dart';\n",
      );
      expect(barrel, contains("import 'dart:async';"));
      expect(barrel, contains("// export 'in_a_comment.dart';"));
      expect(barrel, isNot(contains('stub.dart')));
      expect(barrel, isNot(contains('late.dart')));
    });

    test('it is idempotent: a second run changes nothing', () async {
      final ws = package();
      ws.write({
        'pkg/lib/demo_pkg.dart':
            "library;\nexport \"x.dart\";\nexport 'y.dart' show Y;\n",
      });
      await tool.run(const ['pkg/lib'], workingDirectory: ws.root);
      final first = ws.read('pkg/lib/demo_pkg.dart');
      await tool.run(const ['pkg/lib'], workingDirectory: ws.root);
      expect(ws.read('pkg/lib/demo_pkg.dart'), first);
    });
  });

  group('a directory barrel written by hand is deleted too', () {
    test('only relative exports, no header, either quote style', () async {
      final ws = package();
      ws.write({
        'pkg/lib/src/sub/sub.dart': "export 'q.dart';\n",
        'pkg/lib/src/sub/q.dart': 'class Q {}\n',
        'pkg/lib/src/dq/dq.dart': 'library;\n\nexport "r.dart";\n',
        'pkg/lib/src/dq/r.dart': 'class R {}\n',
        'pkg/lib/src/wrapped/w.dart': "export 's.dart'\n    show S;\n",
        'pkg/lib/src/wrapped/s.dart': 'class S {}\n',
      });
      expect(
        await tool.run(const ['pkg/lib'], workingDirectory: ws.root),
        exitsWith(0),
      );
      for (final gone in [
        'pkg/lib/src/sub/sub.dart',
        'pkg/lib/src/dq/dq.dart',
        'pkg/lib/src/wrapped/w.dart',
      ]) {
        expect(ws.exists(gone), isFalse, reason: gone);
      }
      final barrel = ws.read('pkg/lib/demo_pkg.dart');
      for (final kept in [
        'src/sub/q.dart',
        'src/dq/r.dart',
        'src/wrapped/s.dart',
      ]) {
        expect(barrel, contains("export '$kept';"));
      }
      expect(barrel, isNot(contains('sub.dart')));
      expect(barrel, isNot(contains('dq.dart')));
    });

    test(
      'a deliberate re-export of another package is a regular file',
      () async {
        final ws = package();
        ws.write({
          'pkg/lib/src/kernel.dart':
              '/// Re-exports platform_kernel wholesale.\nlibrary;\n\n'
              "export 'package:platform_kernel/platform_kernel.dart';\n",
          'pkg/lib/src/shown.dart': "export 'package:domain_core/domain_core.dart'\n    show AppFailure;\n",
        });
        expect(
          await tool.run(const ['pkg/lib'], workingDirectory: ws.root),
          exitsWith(0),
        );
        expect(ws.exists('pkg/lib/src/kernel.dart'), isTrue);
        expect(ws.exists('pkg/lib/src/shown.dart'), isTrue);
        expect(
          ws.read('pkg/lib/src/kernel.dart'),
          contains("export 'package:platform_kernel/platform_kernel.dart';"),
        );
        final barrel = ws.read('pkg/lib/demo_pkg.dart');
        expect(barrel, contains("export 'src/kernel.dart';"));
        expect(barrel, contains("export 'src/shown.dart';"));
      },
    );

    test('a file that exports and also holds code is not a barrel', () async {
      final ws = package();
      ws.write({
        'pkg/lib/src/mixed.dart': "export 'a.dart';\nclass Mixed {}\n",
      });
      expect(
        await tool.run(const ['pkg/lib'], workingDirectory: ws.root),
        exitsWith(0),
      );
      expect(ws.exists('pkg/lib/src/mixed.dart'), isTrue);
      expect(ws.read('pkg/lib/src/mixed.dart'), contains('class Mixed'));
    });

    test(
      'the barrel, run twice after a hand-written barrel, is stable',
      () async {
        final ws = package();
        ws.write({
          'pkg/lib/src/sub/sub.dart': "export 'q.dart';\n",
          'pkg/lib/src/sub/q.dart': 'class Q {}\n',
        });
        await tool.run(const ['pkg/lib'], workingDirectory: ws.root);
        final first = ws.read('pkg/lib/demo_pkg.dart');
        await tool.run(const ['pkg/lib'], workingDirectory: ws.root);
        expect(ws.read('pkg/lib/demo_pkg.dart'), first);
        expect(ws.exists('pkg/lib/src/sub/sub.dart'), isFalse);
      },
    );
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
