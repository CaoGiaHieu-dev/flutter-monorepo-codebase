import 'dart:io';

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
        'platform/layers/domain/pubspec.yaml': pubspec('domain_core'),
        'platform/state/provider/pubspec.yaml': pubspec(
          'provider_state_management',
          deps: ['domain_core'],
        ),
        'platform/state/provider/lib/p.dart':
            "import 'package:domain_core/domain_core.dart';\n",
      });
      expectClean(run, 'R1');
    });

    test('a core package importing a feature fails', () async {
      final run = await check({
        'platform/infra/foo/pubspec.yaml': pubspec(
          'core_foo',
          deps: ['feature_bar'],
        ),
        'platform/infra/foo/lib/foo.dart':
            "import 'package:feature_bar/feature_bar.dart';\n",
      });
      expectViolation(run, 'R1', 'platform/infra/foo/lib/foo.dart:1');
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

    test('domain_core and another domain_* package pass', () async {
      final run = await check({
        'platform/layers/domain/pubspec.yaml': pubspec('domain_core'),
        'modules/y/domain/pubspec.yaml': pubspec(
          'domain_y',
          deps: ['domain_core'],
        ),
        'modules/x/domain/pubspec.yaml': pubspec(
          'domain_x',
          deps: ['domain_core', 'domain_y'],
        ),
        'modules/x/domain/lib/x.dart':
            "import 'package:domain_core/domain_core.dart';\n"
            "import 'package:domain_y/domain_y.dart';\n",
      });
      expectClean(run, 'R2');
    });

    for (final dep in [
      'core_network',
      'platform_kernel',
      'data_core',
      'feature_x',
    ]) {
      test('a domain package importing $dep fails', () async {
        final run = await check({
          'modules/x/domain/pubspec.yaml': pubspec('domain_x', deps: [dep]),
          'modules/x/domain/lib/x.dart': "import 'package:$dep/$dep.dart';\n",
        });
        expectViolation(run, 'R2', 'modules/x/domain/lib/x.dart:1');
        expect(run.output, contains('declares `$dep`'));
      });
    }

    test('domain_core declaring a core_* package fails', () async {
      final run = await check({
        'platform/layers/domain/pubspec.yaml': pubspec(
          'domain_core',
          deps: ['core_di'],
        ),
      });
      expectViolation(run, 'R2', 'platform/layers/domain/pubspec.yaml');
    });

    test('a domain package declaring dio fails', () async {
      final run = await check({
        'modules/x/domain/pubspec.yaml': pubspec('domain_x', deps: ['dio']),
      });
      expectViolation(run, 'R2', 'modules/x/domain/pubspec.yaml');
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
        'platform/infra/foo/pubspec.yaml': pubspec('core_foo'),
        'platform/infra/foo/lib/src/utils/foo_keys.dart':
            "class FooKeys {\n  static const String KEY = 'k';\n}\n",
        'platform/infra/foo/lib/src/foo.dart':
            'class Foo {\n  static const _limit = 3;\n'
            '  int get limit => _limit;\n}\n',
      });
      expectClean(run, 'R4');
    });

    test('a public constant outside utils/ fails', () async {
      final run = await check({
        'platform/infra/foo/pubspec.yaml': pubspec('core_foo'),
        'platform/infra/foo/lib/src/foo.dart':
            "class Foo {\n  static const String KEY = 'k';\n}\n",
      });
      expectViolation(run, 'R4', 'platform/infra/foo/lib/src/foo.dart:2');
    });
  });

  group('R5 every import is declared', () {
    test('an import declared under dependencies passes', () async {
      final run = await check({
        'platform/infra/foo/pubspec.yaml': pubspec('core_foo', deps: ['yaml']),
        'platform/infra/foo/lib/foo.dart': "import 'package:yaml/yaml.dart';\n",
      });
      expectClean(run, 'R5');
    });

    test('an import declared only under dev_dependencies fails', () async {
      final run = await check({
        'platform/infra/foo/pubspec.yaml': pubspec(
          'core_foo',
          devDeps: ['yaml'],
        ),
        // A multi-line directive: the `show` clause wraps.
        'platform/infra/foo/lib/foo.dart':
            "import 'package:yaml/yaml.dart'\n    show loadYaml;\n",
      });
      expectViolation(run, 'R5', 'platform/infra/foo/lib/foo.dart:1');
    });
  });

  group('R6 generated files keep their header (warning only)', () {
    test('a generated file with its header raises nothing', () async {
      final run = await check({
        'platform/infra/foo/pubspec.yaml': pubspec('core_foo'),
        'platform/infra/foo/lib/foo.g.dart':
            '// GENERATED CODE - DO NOT MODIFY BY HAND\n',
      });
      expectClean(run, 'R6');
      expect(run.output, isNot(contains('generator header')));
    });

    test('a headerless generated file warns but still exits 0', () async {
      final run = await check({
        'platform/infra/foo/pubspec.yaml': pubspec('core_foo'),
        'platform/infra/foo/lib/foo.g.dart': 'class Edited {}\n',
      });
      expect(run, exitsWith(0));
      expect(run.output, contains('1 warning(s)'));
      expect(run.output, contains('platform/infra/foo/lib/foo.g.dart'));
      expect(run.output, contains('generator header'));
    });
  });

  group('R7 responsive sizing goes through BuildContext', () {
    const header = "import 'package:core_responsive/core_responsive.dart';\n";

    test('context.w(...) and a commented 16.w pass', () async {
      final run = await check({
        'platform/infra/foo/pubspec.yaml': pubspec(
          'core_foo',
          deps: ['core_responsive'],
        ),
        'platform/infra/foo/lib/foo.dart':
            '$header'
            'double pad(dynamic context) => context.w(16); // not 16.w\n',
      });
      expectClean(run, 'R7');
    });

    test('a bare 16.h fails', () async {
      final run = await check({
        'platform/infra/foo/pubspec.yaml': pubspec(
          'core_foo',
          deps: ['core_responsive'],
        ),
        'platform/infra/foo/lib/foo.dart': '${header}final gap = 16.h;\n',
      });
      expectViolation(run, 'R7', 'platform/infra/foo/lib/foo.dart:2');
    });
  });

  group('R8 removable contracts resolve optionally', () {
    /// `IFooContract` is declared in core_di and implemented only in
    /// `modules/foo`, so it disappears when that module is removed.
    Map<String, String> contractFixture(String shellLookup) => {
      'platform/foundation/contracts/pubspec.yaml': pubspec('core_di'),
      'platform/foundation/contracts/lib/i_foo_contract.dart':
          'abstract class IFooContract {}\n',
      'modules/foo/feature/pubspec.yaml': pubspec(
        'feature_foo',
        deps: ['core_di'],
      ),
      'modules/foo/feature/lib/foo.dart':
          "import 'package:core_di/core_di.dart';\n"
          'class FooImpl implements IFooContract {}\n'
          // The owning module may resolve its own contract eagerly.
          'final own = getIt<IFooContract>();\n',
      'platform/shell/app_shell/pubspec.yaml': pubspec(
        'platform_app_shell',
        deps: ['core_di'],
      ),
      'platform/shell/app_shell/lib/shell.dart':
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
      expectViolation(run, 'R8', 'platform/shell/app_shell/lib/shell.dart:2');
      expect(run.output, contains('modules/foo'));
    });
  });

  group('R9 the pure-Dart tier stays pure', () {
    test('platform_kernel with pure-Dart dependencies passes', () async {
      final run = await check({
        'platform/foundation/kernel/pubspec.yaml': pubspec(
          'platform_kernel',
          deps: ['path'],
        ),
        'platform/foundation/kernel/lib/k.dart':
            "import 'package:path/path.dart';\n",
      });
      expectClean(run, 'R9');
    });

    test('platform_kernel declaring flutter fails', () async {
      final run = await check({
        'platform/foundation/kernel/pubspec.yaml': pubspec(
          'platform_kernel',
          deps: ['flutter'],
        ),
      });
      expectViolation(run, 'R9', 'platform/foundation/kernel/pubspec.yaml');
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
  group('R11 platform group direction', () {
    /// Every group, wired along each edge the DAG allows — dev dependency
    /// against the grain included, which R11 ignores. (An edge into
    /// `domain_core` / `data_core` also needs R1's approved list, so the
    /// fixture uses only the approved `provider_state_management` one.)
    Map<String, String> dag() => {
      'platform/layers/domain/pubspec.yaml': pubspec('domain_core'),
      'platform/foundation/kernel/pubspec.yaml': pubspec(
        'platform_kernel',
        deps: ['domain_core'],
      ),
      'platform/foundation/contracts/pubspec.yaml': pubspec('core_di'),
      'platform/foundation/common/pubspec.yaml': pubspec(
        'core_common',
        deps: ['platform_kernel', 'core_di'],
      ),
      'platform/layers/data/pubspec.yaml': pubspec(
        'data_core',
        deps: ['platform_kernel', 'domain_core'],
      ),
      'platform/infra/network/pubspec.yaml': pubspec(
        'core_network',
        deps: ['platform_kernel'],
      ),
      'platform/ui/responsive/pubspec.yaml': pubspec('core_responsive'),
      'platform/ui/ui_kit/pubspec.yaml': pubspec(
        'core_ui_kit',
        deps: ['core_common', 'core_responsive'],
        devDeps: ['provider_state_management'],
      ),
      'platform/state/provider/pubspec.yaml': pubspec(
        'provider_state_management',
        deps: ['core_ui_kit', 'domain_core'],
      ),
      'platform/shell/adapters/pubspec.yaml': pubspec(
        'platform_shell_adapters',
        deps: ['core_network', 'core_ui_kit'],
      ),
      'platform/shell/app_shell/pubspec.yaml': pubspec(
        'platform_app_shell',
        deps: [
          'platform_shell_adapters',
          'provider_state_management',
          'core_common',
        ],
      ),
    };

    test('every allowed edge (and a dev dependency) passes', () async {
      final run = await check(dag());
      expectClean(run, 'R11');
    });

    test('ui depending on state fails', () async {
      final run = await check({
        ...dag(),
        'platform/ui/ui_kit/pubspec.yaml': pubspec(
          'core_ui_kit',
          deps: ['core_common', 'provider_state_management'],
        ),
      });
      expectViolation(run, 'R11', 'platform/ui/ui_kit/pubspec.yaml');
      expect(
        run.output,
        contains('depends on `provider_state_management` (platform/state)'),
      );
    });

    test('infra depending on infra fails', () async {
      final run = await check({
        ...dag(),
        'platform/infra/storage/pubspec.yaml': pubspec(
          'core_storage',
          deps: ['core_network'],
        ),
      });
      expectViolation(run, 'R11', 'platform/infra/storage/pubspec.yaml');
    });

    test('domain_core depending on anything in platform/ fails', () async {
      final run = await check({
        ...dag(),
        'platform/layers/domain/pubspec.yaml': pubspec(
          'domain_core',
          deps: ['core_di'],
        ),
      });
      expectViolation(run, 'R11', 'platform/layers/domain/pubspec.yaml');
      expect(run.output, contains('no other platform package'));
    });

    test('foundation depending on shell fails', () async {
      final run = await check({
        ...dag(),
        'platform/foundation/common/pubspec.yaml': pubspec(
          'core_common',
          deps: ['platform_app_shell'],
        ),
      });
      expectViolation(run, 'R11', 'platform/foundation/common/pubspec.yaml');
    });

    test('a package outside a group folder fails', () async {
      final run = await check({
        'platform/stray/pubspec.yaml': pubspec('core_stray'),
      });
      expectViolation(run, 'R11', 'platform/stray/pubspec.yaml');
      expect(run.output, contains('not in a platform group folder'));
    });
  });

  group('R12 no PowerShell scripts', () {
    test('.sh, .bat and Dart scripts pass', () async {
      final run = await check({
        'platform/infra/foo/pubspec.yaml': pubspec('core_foo'),
        'tools/x/run.sh': 'echo ok\n',
        'tools/x/run.bat': '@echo ok\n',
        'tools/x/run.dart': 'void main() {}\n',
      });
      expectClean(run, 'R12');
    });

    test('a .ps1 anywhere fails', () async {
      final run = await check({
        'platform/infra/foo/pubspec.yaml': pubspec('core_foo'),
        'tools/x/Setup.PS1': 'Write-Host ok\n',
      });
      expectViolation(run, 'R12', 'tools/x/Setup.PS1');
    });

    test('a .ps1 git ignores is skipped, an untracked one is not', () async {
      final ws = TempWorkspace.create({
        'pubspec.yaml': 'name: ws\n',
        'platform/infra/foo/pubspec.yaml': pubspec('core_foo'),
        '.gitignore': 'local/\n',
        'local/mine.ps1': 'Write-Host ok\n',
        'tools/shared.ps1': 'Write-Host ok\n',
      });
      final init = await Process.run('git', [
        'init',
        '-q',
      ], workingDirectory: ws.root);
      expect(init.exitCode, 0, reason: '${init.stderr}');
      final run = await tool.run(const [], workingDirectory: ws.root);
      // Untracked but not ignored: about to be committed, so reported.
      expectViolation(run, 'R12', 'tools/shared.ps1');
      expect(run.output, isNot(contains('local/mine.ps1')));
    });
  });

  group('R13 no analyzer suppressions', () {
    test(
      'the words in a string, a doc comment or generated code pass',
      () async {
        final run = await check({
          'platform/infra/foo/pubspec.yaml': pubspec('core_foo'),
          'platform/infra/foo/lib/foo.dart':
              '/// Never write `// ignore: x`.\n'
              "const tip = '// ignore: not a comment';\n"
              "const t2 = '''\n// ignore_for_file: template text\n''';\n",
          'platform/infra/foo/lib/foo.g.dart':
              '// GENERATED CODE - DO NOT MODIFY BY HAND\n'
              '// ignore_for_file: type=lint\n',
          'platform/infra/foo/lib/src/gen/assets.dart':
              '// ignore_for_file: type=lint\n',
        });
        expectClean(run, 'R13');
      },
    );

    test('ignore and ignore_for_file comments fail, in tools/ too', () async {
      final run = await check({
        'platform/infra/foo/pubspec.yaml': pubspec('core_foo'),
        'platform/infra/foo/test/foo_test.dart':
            '// ignore_for_file: avoid_print\nvoid main() {}\n',
        'tools/x/run.dart':
            'void main() {\n'
            "  final s = '\${1}'; // ignore: unused_local_variable\n"
            '}\n',
      });
      expectViolation(run, 'R13', 'platform/infra/foo/test/foo_test.dart:1');
      expect(run.output, contains('tools/x/run.dart:2'));
    });
  });

  group('R14 data_sources/, never datasources/', () {
    test('data_sources/ passes', () async {
      final run = await check({
        'modules/a/data/pubspec.yaml': pubspec('data_a'),
        'modules/a/data/lib/src/data_sources/remote/a_remote.dart': '',
      });
      expectClean(run, 'R14');
    });

    test('a datasources/ folder fails, empty or not', () async {
      final ws = TempWorkspace.create({
        'pubspec.yaml': 'name: ws\n',
        'modules/a/data/pubspec.yaml': pubspec('data_a'),
        'modules/a/data/lib/src/datasources/a_remote.dart': '',
      });
      ws.mkdir('platform/infra/foo/lib/dataSources');
      final run = await tool.run(const [], workingDirectory: ws.root);
      expectViolation(run, 'R14', 'modules/a/data/lib/src/datasources');
      expect(run.output, contains('platform/infra/foo/lib/dataSources'));
    });
  });

  group('R15 the I prefix is reserved for interfaces', () {
    test('abstract, interface and sealed I-types pass', () async {
      final run = await check({
        'platform/infra/foo/pubspec.yaml': pubspec('core_foo'),
        'platform/infra/foo/lib/foo.dart':
            'abstract class IFoo {}\n'
            'abstract interface class IBar {}\n'
            'interface class IBaz {}\n'
            'sealed class IQux {}\n'
            'abstract mixin class IMix {}\n'
            'mixin IPlainMixin {}\n'
            'class Icon {}\n'
            'class FooImpl implements IFoo {}\n'
            '// class INotCode {}\n'
            "const template = 'class ITemplate {}';\n",
        // Outside modules/, platform/ and apps/*/lib: not checked.
        'tools/x/fake.dart': 'class IToolFake {}\n',
        'apps/demo/test/fake.dart': 'class ITestFake {}\n',
      });
      expectClean(run, 'R15');
    });

    test('a concrete I-named class fails, modifiers or not', () async {
      final run = await check({
        'platform/infra/foo/pubspec.yaml': pubspec('core_foo'),
        'modules/a/feature/pubspec.yaml': pubspec('feature_a'),
        'modules/a/feature/lib/a.dart':
            '@immutable\n'
            'class IAuthProvider {}\n'
            'final class IFinal {}\n',
        'apps/demo/lib/main.dart': '@immutable class IAppThing {}\n',
      });
      expectViolation(run, 'R15', 'modules/a/feature/lib/a.dart:2');
      expect(run.output, contains('modules/a/feature/lib/a.dart:3'));
      expect(run.output, contains('apps/demo/lib/main.dart:1'));
      expect(run.output, contains('`AuthProviderImpl`'));
    });
  });

  group('R3 / R8 module API packages', () {
    /// Module `a` publishes `ANavigator` through `a_api` and implements it
    /// in `feature_a`; module `b`'s feature consumes it.
    Map<String, String> apiFixture({
      String apiImport = '',
      List<String> apiDeps = const ['flutter', 'core_di'],
      String consumerLookup = 'final nav = getItOrNull<ANavigator>();',
    }) => {
      'platform/foundation/contracts/pubspec.yaml': pubspec('core_di'),
      'platform/ui/ui_kit/pubspec.yaml': pubspec('core_ui_kit'),
      'modules/a/api/pubspec.yaml': pubspec('a_api', deps: apiDeps),
      'modules/a/api/lib/a_api.dart':
          "import 'package:flutter/widgets.dart';\n"
          '$apiImport'
          'abstract class ANavigator {\n'
          '  void toA(BuildContext context);\n'
          '}\n',
      'modules/a/domain/pubspec.yaml': pubspec('domain_a'),
      'modules/a/feature/pubspec.yaml': pubspec(
        'feature_a',
        deps: ['a_api'],
      ),
      'modules/a/feature/lib/a.dart':
          "import 'package:a_api/a_api.dart';\n"
          'class ANavigatorImpl implements ANavigator {}\n',
      'modules/b/api/pubspec.yaml': pubspec('b_api'),
      'modules/b/feature/pubspec.yaml': pubspec(
        'feature_b',
        deps: ['a_api', 'core_di'],
      ),
      'modules/b/feature/lib/b.dart':
          "import 'package:a_api/a_api.dart';\n"
          "import 'package:core_di/core_di.dart';\n"
          '$consumerLookup\n',
    };

    test("a feature using another module's API optionally passes", () async {
      final run = await check(apiFixture());
      expectClean(run, 'R3');
      expect(run.output, isNot(contains('R8 — ')));
    });

    test('an API package importing its own domain fails', () async {
      final run = await check(
        apiFixture(
          apiImport: "import 'package:domain_a/domain_a.dart';\n",
          apiDeps: ['flutter', 'domain_a'],
        ),
      );
      expectViolation(run, 'R3', 'modules/a/api/lib/a_api.dart:2');
      expect(run.output, contains('(a module package)'));
      expect(run.output, contains('modules/a/api/pubspec.yaml'));
    });

    test("an API package importing another module's API fails", () async {
      final run = await check(
        apiFixture(
          apiImport: "import 'package:b_api/b_api.dart';\n",
          apiDeps: ['flutter', 'b_api'],
        ),
      );
      expectViolation(run, 'R3', 'modules/a/api/lib/a_api.dart:2');
      expect(run.output, contains("(another module's API)"));
    });

    test(
      'an API package declaring a non-foundation platform package fails',
      () async {
        final run = await check(
          apiFixture(apiDeps: ['flutter', 'core_ui_kit']),
        );
        expectViolation(run, 'R3', 'modules/a/api/pubspec.yaml');
        expect(run.output, contains('(platform/ui)'));
      },
    );

    test('a throwing lookup of an API type outside its module fails', () async {
      final run = await check(
        apiFixture(consumerLookup: 'final nav = getIt<ANavigator>();'),
      );
      expectViolation(run, 'R8', 'modules/b/feature/lib/b.dart:3');
      expect(run.output, contains('modules/a'));
    });

    test('a platform package importing an API package fails (R1)', () async {
      final run = await check({
        ...apiFixture(),
        'platform/shell/app_shell/pubspec.yaml': pubspec(
          'platform_app_shell',
          deps: ['a_api'],
        ),
        'platform/shell/app_shell/lib/shell.dart':
            "import 'package:a_api/a_api.dart';\n",
      });
      expectViolation(run, 'R1', 'platform/shell/app_shell/lib/shell.dart:1');
    });

    test('an app file importing an API package fails (R10)', () async {
      final run = await check({
        ...apiFixture(),
        'apps/demo/app_manifest.yaml': 'app:\n  id: demo\n',
        'apps/demo/pubspec.yaml': pubspec('demo_app', deps: ['a_api']),
        'apps/demo/lib/main.dart': "import 'package:a_api/a_api.dart';\n",
      });
      expectViolation(run, 'R10', 'apps/demo/lib/main.dart:1');
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
