import 'package:test/test.dart';

import 'support/tool_harness.dart';

/// `tools/arch_check/check.dart` — CI Gate 1.
///
/// One clean and one violating fixture per rule. Each fixture is a complete,
/// minimal workspace, so a rule is proven to fire on its own trigger and to
/// stay quiet on the pattern it is meant to allow — not merely on a tree that
/// happens to contain neither.
void main() {
  late CompiledTool tool;

  setUpAll(() async {
    tool = await CompiledTool.compile('tools/arch_check/check.dart');
  });
  tearDownAll(() => tool.dispose());

  Future<ToolRun> check(Map<String, String> files) {
    final ws = TempWorkspace.create({'pubspec.yaml': 'name: ws\n', ...files});
    return tool.run(const [], workingDirectory: ws.root);
  }

  /// Asserts [run] passed and that [rule]'s section is absent.
  void expectClean(ToolRun run, String rule) {
    expect(run, exitsWith(0));
    expect(run.output, isNot(contains('$rule — ')));
    expect(run.output, contains('All architecture rules hold'));
  }

  /// Asserts [run] failed on [rule] and pointed at [location].
  void expectViolation(ToolRun run, String rule, String location) {
    expect(run, exitsWith(1));
    expect(run.output, contains('$rule — '));
    expect(run.output, contains(location));
  }

  test('an empty workspace is a failure, never a clean pass', () async {
    final run = await check(const {});
    expect(run, exitsWith(1));
    expect(run.output, contains('No workspace packages found'));
  });

  test('an unknown argument exits 64', () async {
    final ws = TempWorkspace.create({'pubspec.yaml': 'name: ws\n'});
    final run = await tool.run(const ['--fix'], workingDirectory: ws.root);
    expect(run, exitsWith(64));
  });

  group('R1 dependency direction', () {
    test('an approved core -> domain_core edge passes', () async {
      final run = await check({
        'platform/domain_core/pubspec.yaml': pubspec('domain_core'),
        'platform/provider_state_management/pubspec.yaml': pubspec(
          'provider_state_management',
          deps: ['domain_core'],
        ),
        'platform/provider_state_management/lib/p.dart':
            "import 'package:domain_core/domain_core.dart';\n",
      });
      expectClean(run, 'R1');
    });

    test('a core package importing a feature fails', () async {
      final run = await check({
        'platform/foo/pubspec.yaml': pubspec('core_foo', deps: ['feature_bar']),
        'platform/foo/lib/foo.dart':
            "import 'package:feature_bar/feature_bar.dart';\n",
      });
      expectViolation(run, 'R1', 'platform/foo/lib/foo.dart:1');
      expect(run.output, contains('declares `feature_bar`'));
    });
  });

  group('R2 domain is pure Dart', () {
    test('a dev-only flutter dependency and dart: imports pass', () async {
      final run = await check({
        'modules/x/domain/pubspec.yaml': pubspec(
          'domain_x',
          devDeps: ['flutter'],
        ),
        'modules/x/domain/lib/x.dart': "import 'dart:async';\n",
      });
      expectClean(run, 'R2');
    });

    test('a domain package importing flutter fails', () async {
      final run = await check({
        'modules/x/domain/pubspec.yaml': pubspec('domain_x'),
        'modules/x/domain/lib/x.dart':
            "import 'package:flutter/foundation.dart';\n",
      });
      expectViolation(run, 'R2', 'modules/x/domain/lib/x.dart:1');
    });
  });

  group('R3 feature boundaries', () {
    test('a feature importing its domain passes', () async {
      final run = await check({
        'modules/a/feature/pubspec.yaml': pubspec(
          'feature_a',
          deps: ['domain_a'],
        ),
        'modules/a/feature/lib/a.dart':
            "import 'package:domain_a/domain_a.dart';\n",
      });
      expectClean(run, 'R3');
    });

    test('a feature importing another feature fails', () async {
      final run = await check({
        'modules/a/feature/pubspec.yaml': pubspec(
          'feature_a',
          deps: ['feature_b'],
        ),
        'modules/a/feature/lib/a.dart':
            "import 'package:feature_b/feature_b.dart';\n",
      });
      expectViolation(run, 'R3', 'modules/a/feature/lib/a.dart:1');
      expect(run.output, contains('imports another feature `feature_b`'));
    });
  });

  group('R4 constants live in utils/', () {
    test('public constants in utils/ and private ones anywhere pass', () async {
      final run = await check({
        'platform/foo/pubspec.yaml': pubspec('core_foo'),
        'platform/foo/lib/src/utils/foo_keys.dart':
            "class FooKeys {\n  static const String KEY = 'k';\n}\n",
        'platform/foo/lib/src/foo.dart':
            'class Foo {\n  static const _limit = 3;\n'
            '  int get limit => _limit;\n}\n',
      });
      expectClean(run, 'R4');
    });

    test('a public constant outside utils/ fails', () async {
      final run = await check({
        'platform/foo/pubspec.yaml': pubspec('core_foo'),
        'platform/foo/lib/src/foo.dart':
            "class Foo {\n  static const String KEY = 'k';\n}\n",
      });
      expectViolation(run, 'R4', 'platform/foo/lib/src/foo.dart:2');
    });
  });

  group('R5 every import is declared', () {
    test('an import declared under dependencies passes', () async {
      final run = await check({
        'platform/foo/pubspec.yaml': pubspec('core_foo', deps: ['yaml']),
        'platform/foo/lib/foo.dart': "import 'package:yaml/yaml.dart';\n",
      });
      expectClean(run, 'R5');
    });

    test('an import declared only under dev_dependencies fails', () async {
      final run = await check({
        'platform/foo/pubspec.yaml': pubspec('core_foo', devDeps: ['yaml']),
        // A multi-line directive: the `show` clause wraps.
        'platform/foo/lib/foo.dart':
            "import 'package:yaml/yaml.dart'\n    show loadYaml;\n",
      });
      expectViolation(run, 'R5', 'platform/foo/lib/foo.dart:1');
    });
  });

  group('R6 generated files keep their header (warning only)', () {
    test('a generated file with its header raises nothing', () async {
      final run = await check({
        'platform/foo/pubspec.yaml': pubspec('core_foo'),
        'platform/foo/lib/foo.g.dart':
            '// GENERATED CODE - DO NOT MODIFY BY HAND\n',
      });
      expectClean(run, 'R6');
      expect(run.output, isNot(contains('generator header')));
    });

    test('a headerless generated file warns but still exits 0', () async {
      final run = await check({
        'platform/foo/pubspec.yaml': pubspec('core_foo'),
        'platform/foo/lib/foo.g.dart': 'class Edited {}\n',
      });
      expect(run, exitsWith(0));
      expect(run.output, contains('1 warning(s)'));
      expect(run.output, contains('platform/foo/lib/foo.g.dart'));
      expect(run.output, contains('generator header'));
    });
  });

  group('R7 responsive sizing goes through BuildContext', () {
    const header = "import 'package:core_responsive/core_responsive.dart';\n";

    test('context.w(...) and a commented 16.w pass', () async {
      final run = await check({
        'platform/foo/pubspec.yaml': pubspec(
          'core_foo',
          deps: ['core_responsive'],
        ),
        'platform/foo/lib/foo.dart':
            '$header'
            'double pad(dynamic context) => context.w(16); // not 16.w\n',
      });
      expectClean(run, 'R7');
    });

    test('a bare 16.h fails', () async {
      final run = await check({
        'platform/foo/pubspec.yaml': pubspec(
          'core_foo',
          deps: ['core_responsive'],
        ),
        'platform/foo/lib/foo.dart': '${header}final gap = 16.h;\n',
      });
      expectViolation(run, 'R7', 'platform/foo/lib/foo.dart:2');
    });
  });

  group('R8 removable contracts resolve optionally', () {
    /// `IFooContract` is declared in core_di and implemented only in
    /// `modules/foo`, so it disappears when that module is removed.
    Map<String, String> contractFixture(String shellLookup) => {
      'platform/di/pubspec.yaml': pubspec('core_di'),
      'platform/di/lib/i_foo_contract.dart': 'abstract class IFooContract {}\n',
      'modules/foo/feature/pubspec.yaml': pubspec(
        'feature_foo',
        deps: ['core_di'],
      ),
      'modules/foo/feature/lib/foo.dart':
          "import 'package:core_di/core_di.dart';\n"
          'class FooImpl implements IFooContract {}\n'
          // The owning module may resolve its own contract eagerly.
          'final own = getIt<IFooContract>();\n',
      'platform/shell/pubspec.yaml': pubspec(
        'platform_app_shell',
        deps: ['core_di'],
      ),
      'platform/shell/lib/shell.dart':
          "import 'package:core_di/core_di.dart';\n$shellLookup\n",
    };

    test('getItOrNull outside the module, getIt inside it, pass', () async {
      final run = await check(
        contractFixture('final foo = getItOrNull<IFooContract>();'),
      );
      expectClean(run, 'R8');
    });

    test('a throwing getIt outside the owning module fails', () async {
      final run = await check(
        contractFixture('final foo = getIt<IFooContract>();'),
      );
      expectViolation(run, 'R8', 'platform/shell/lib/shell.dart:2');
      expect(run.output, contains('modules/foo'));
    });
  });

  group('R9 the pure-Dart tier stays pure', () {
    test('platform_kernel with pure-Dart dependencies passes', () async {
      final run = await check({
        'platform/kernel/pubspec.yaml': pubspec(
          'platform_kernel',
          deps: ['path'],
        ),
        'platform/kernel/lib/k.dart': "import 'package:path/path.dart';\n",
      });
      expectClean(run, 'R9');
    });

    test('platform_kernel declaring flutter fails', () async {
      final run = await check({
        'platform/kernel/pubspec.yaml': pubspec(
          'platform_kernel',
          deps: ['flutter'],
        ),
      });
      expectViolation(run, 'R9', 'platform/kernel/pubspec.yaml');
    });
  });

  group('R10 the app shell composes modules, it does not import them', () {
    Map<String, String> app(String mainImport) => {
      'apps/demo/app_manifest.yaml': 'app:\n  id: demo\n',
      'apps/demo/pubspec.yaml': pubspec('demo_app', deps: ['feature_foo']),
      'apps/demo/lib/di/injection.dart':
          "import 'package:feature_foo/di/module.module.dart';\n",
      'apps/demo/lib/main.dart': mainImport,
    };

    test('only injection.dart naming a module passes', () async {
      final run = await check(app("import 'dart:async';\n"));
      expectClean(run, 'R10');
    });

    test('any other app file importing a module fails', () async {
      final run = await check(
        app("import 'package:feature_foo/feature_foo.dart';\n"),
      );
      expectViolation(run, 'R10', 'apps/demo/lib/main.dart:1');
      expect(run.output, isNot(contains('injection.dart:1')));
    });
  });
}

/// A minimal pubspec. `flutter` is written as an SDK dependency.
String pubspec(
  String name, {
  List<String> deps = const [],
  List<String> devDeps = const [],
}) {
  String section(String title, List<String> names) {
    if (names.isEmpty) return '';
    final lines = [
      for (final n in names)
        n == 'flutter' ? '  flutter:\n    sdk: flutter' : '  $n: any',
    ];
    return '$title:\n${lines.join('\n')}\n';
  }

  return 'name: $name\n'
      '${section('dependencies', deps)}'
      '${section('dev_dependencies', devDeps)}';
}
