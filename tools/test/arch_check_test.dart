import 'dart:io';

import 'package:test/test.dart';

import '../arch_check/platform_forks.dart';
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
        'modules/bar/feature/pubspec.yaml': pubspec('feature_bar'),
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

    test('the approved data_core -> domain_core edge passes', () async {
      final run = await check({
        'platform/layers/domain/pubspec.yaml': pubspec('domain_core'),
        'platform/layers/data/pubspec.yaml': pubspec(
          'data_core',
          deps: ['domain_core'],
        ),
        'platform/layers/data/lib/d.dart':
            "import 'package:domain_core/domain_core.dart';\n"
            "import 'package:data_core/src/x.dart';\n",
      });
      expectClean(run, 'R1');
    });

    test('data_core importing and declaring a feature fails', () async {
      final run = await check({
        'modules/auth/feature/pubspec.yaml': pubspec('feature_auth'),
        'platform/layers/data/pubspec.yaml': pubspec(
          'data_core',
          deps: ['feature_auth'],
        ),
        'platform/layers/data/lib/d.dart':
            "import 'package:feature_auth/feature_auth.dart';\n",
      });
      expectViolation(run, 'R1', 'platform/layers/data/lib/d.dart:1');
      expect(run.output, contains('core package `data_core` imports'));
      expect(run.output, contains('platform/layers/data/pubspec.yaml'));
      expect(run.output, contains('core package `data_core` declares'));
    });

    test('data_core importing a module API package fails', () async {
      final run = await check({
        'modules/home/api/pubspec.yaml': pubspec('home_api'),
        'platform/layers/data/pubspec.yaml': pubspec(
          'data_core',
          deps: ['home_api'],
        ),
        'platform/layers/data/lib/d.dart':
            "import 'package:home_api/home_api.dart';\n",
      });
      expectViolation(run, 'R1', 'platform/layers/data/lib/d.dart:1');
      expect(run.output, contains('imports `home_api`'));
    });

    test('domain_core importing and declaring a module domain fails', () async {
      final run = await check({
        'modules/auth/domain/pubspec.yaml': pubspec('domain_auth'),
        'platform/layers/domain/pubspec.yaml': pubspec(
          'domain_core',
          deps: ['domain_auth'],
        ),
        'platform/layers/domain/lib/d.dart':
            "import 'package:domain_auth/domain_auth.dart';\n",
      });
      expectViolation(run, 'R1', 'platform/layers/domain/lib/d.dart:1');
      expect(run.output, contains('core package `domain_core` declares'));
      expect(run.output, contains('platform/layers/domain/pubspec.yaml'));
    });

    test('an unapproved platform edge into domain_core still fails', () async {
      final run = await check({
        'platform/layers/domain/pubspec.yaml': pubspec('domain_core'),
        'platform/infra/net/pubspec.yaml': pubspec(
          'core_net',
          deps: ['domain_core'],
        ),
        'platform/infra/net/lib/n.dart':
            "import 'package:domain_core/domain_core.dart';\n",
      });
      expectViolation(run, 'R1', 'platform/infra/net/lib/n.dart:1');
    });

    test('a platform package is core wherever its name points', () async {
      final run = await check({
        'modules/x/feature/pubspec.yaml': pubspec('feature_x'),
        'platform/infra/odd/pubspec.yaml': pubspec(
          'data_odd',
          deps: ['feature_x'],
        ),
      });
      expectViolation(run, 'R1', 'platform/infra/odd/pubspec.yaml');
    });
  });

  group('R2 domain is pure Dart', () {
    test('dart: imports and a pure-Dart dev dependency pass', () async {
      final run = await check({
        'modules/x/domain/pubspec.yaml': pubspec(
          'domain_x',
          devDeps: ['test'],
        ),
        'modules/x/domain/lib/x.dart':
            "import 'dart:async';\nimport 'dart:convert';\n",
        'modules/x/domain/test/x_test.dart':
            "import 'package:test/test.dart';\n",
      });
      expectClean(run, 'R2');
    });

    test('a Flutter dev dependency or test import fails too', () async {
      final run = await check({
        'modules/x/domain/pubspec.yaml': pubspec(
          'domain_x',
          devDeps: ['flutter_test'],
        ),
        'modules/x/domain/test/x_test.dart':
            "import 'package:flutter_test/flutter_test.dart';\n",
      });
      expectViolation(run, 'R2', 'modules/x/domain/pubspec.yaml');
      expect(run.output, contains('declares under `dev_dependencies:`'));
      expect(run.output, contains('modules/x/domain/test/x_test.dart:1'));
      expect(run.output, contains('imports from a test'));
    });

    for (final lib in [
      'ui',
      'html',
      'js',
      'js_interop',
      'js_util',
      'web_ui',
    ]) {
      test('a domain importing dart:$lib fails; the kernel too (R9)', () async {
        final run = await check({
          'modules/x/domain/pubspec.yaml': pubspec('domain_x'),
          'modules/x/domain/lib/x.dart': "import 'dart:$lib';\n",
          'platform/foundation/kernel/pubspec.yaml': pubspec(
            'platform_kernel',
          ),
          'platform/foundation/kernel/lib/k.dart':
              "import 'dart:$lib' show Color;\n",
        });
        expectViolation(run, 'R2', 'modules/x/domain/lib/x.dart:1');
        expect(run.output, contains('imports `dart:$lib`'));
        expect(run.output, contains('R9 — '));
        expect(run.output, contains('platform/foundation/kernel/lib/k.dart:1'));
        expect(run.output, contains('Flutter-engine or browser-only'));
      });
    }

    test('dart:io and dart:async are not engine-only', () async {
      final run = await check({
        'modules/x/domain/pubspec.yaml': pubspec('domain_x'),
        'modules/x/domain/lib/x.dart':
            "import 'dart:io';\nimport 'dart:isolate';\n",
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

    test('domain_core passes', () async {
      final run = await check({
        'platform/layers/domain/pubspec.yaml': pubspec('domain_core'),
        'modules/x/domain/pubspec.yaml': pubspec(
          'domain_x',
          deps: ['domain_core'],
        ),
        'modules/x/domain/lib/x.dart':
            "import 'package:domain_core/domain_core.dart';\n",
      });
      expectClean(run, 'R2');
    });

    test(
      "another module's domain package fails, imported or declared",
      () async {
        final run = await check({
          'modules/y/domain/pubspec.yaml': pubspec('domain_y'),
          'modules/x/domain/pubspec.yaml': pubspec(
            'domain_x',
            deps: ['domain_y'],
          ),
          'modules/x/domain/lib/x.dart':
              "import 'package:domain_y/domain_y.dart';\n",
        });
        expectViolation(run, 'R2', 'modules/x/domain/lib/x.dart:1');
        expect(run.output, contains("another module's domain package"));
        expect(run.output, contains('modules/x/domain/pubspec.yaml'));
      },
    );

    for (final entry in {
      'core_network': 'platform/infra/network',
      'platform_kernel': 'platform/foundation/kernel',
      'data_core': 'platform/layers/data',
      'feature_x': 'modules/x/feature',
    }.entries) {
      final dep = entry.key;
      test('a domain package importing $dep fails', () async {
        final run = await check({
          '${entry.value}/pubspec.yaml': pubspec(dep),
          'modules/x/domain/pubspec.yaml': pubspec('domain_x', deps: [dep]),
          'modules/x/domain/lib/x.dart': "import 'package:$dep/$dep.dart';\n",
        });
        expectViolation(run, 'R2', 'modules/x/domain/lib/x.dart:1');
        expect(run.output, contains('declares `$dep`'));
      });
    }

    test('domain_core declaring a core_* package fails', () async {
      final run = await check({
        'platform/foundation/contracts/pubspec.yaml': pubspec('core_di'),
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

    for (final dep in ['retrofit', 'drift', 'go_router', 'http']) {
      test('a domain package declaring and importing $dep fails', () async {
        final run = await check({
          'modules/x/domain/pubspec.yaml': pubspec('domain_x', deps: [dep]),
          'modules/x/domain/lib/x.dart': "import 'package:$dep/$dep.dart';\n",
        });
        expectViolation(run, 'R2', 'modules/x/domain/lib/x.dart:1');
        expect(run.output, contains('modules/x/domain/pubspec.yaml'));
        expect(run.output, contains('transport or persistence'));
      });
    }

    test('a domain package using a module API package fails', () async {
      final run = await check({
        'modules/a/api/pubspec.yaml': pubspec('a_api'),
        'modules/x/domain/pubspec.yaml': pubspec('domain_x', deps: ['a_api']),
        'modules/x/domain/lib/x.dart': "import 'package:a_api/a_api.dart';\n",
      });
      expectViolation(run, 'R2', 'modules/x/domain/lib/x.dart:1');
      expect(run.output, contains('a module API package'));
    });

    test('a domain package declaring a Flutter plugin fails', () async {
      final run = await check({
        ...hostedPackages({
          'fancy_plugin':
              'name: fancy_plugin\nflutter:\n  plugin:\n'
              '    platforms:\n      android:\n        package: x\n',
        }),
        'modules/x/domain/pubspec.yaml': pubspec(
          'domain_x',
          deps: ['fancy_plugin'],
        ),
      });
      expectViolation(run, 'R2', 'modules/x/domain/pubspec.yaml');
      expect(run.output, contains('a Flutter plugin'));
    });

    test('domain_core importing flutter fails like any domain', () async {
      final run = await check({
        'platform/layers/domain/pubspec.yaml': pubspec('domain_core'),
        'platform/layers/domain/lib/d.dart':
            "import 'package:flutter/foundation.dart';\n",
      });
      expectViolation(run, 'R2', 'platform/layers/domain/lib/d.dart:1');
    });
  });

  group('R3 feature boundaries', () {
    test('a feature importing its domain passes', () async {
      final run = await check({
        'modules/a/domain/pubspec.yaml': pubspec('domain_a'),
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
        'modules/b/feature/pubspec.yaml': pubspec('feature_b'),
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

    test(
      'a feature declaring another feature, never importing it, fails',
      () async {
        final run = await check({
          'modules/b/feature/pubspec.yaml': pubspec('feature_b'),
          'modules/a/feature/pubspec.yaml': pubspec(
            'feature_a',
            deps: ['feature_b'],
          ),
          'modules/a/feature/lib/a.dart': 'const a = 1;\n',
        });
        expectViolation(run, 'R3', 'modules/a/feature/pubspec.yaml');
        expect(run.output, contains('declares another feature `feature_b`'));
      },
    );

    test(
      'a feature declaring a data package, never importing it, fails',
      () async {
        final run = await check({
          'modules/a/data/pubspec.yaml': pubspec('data_a'),
          'modules/a/feature/pubspec.yaml': pubspec(
            'feature_a',
            deps: ['data_a'],
          ),
        });
        expectViolation(run, 'R3', 'modules/a/feature/pubspec.yaml');
        expect(run.output, contains('declares data package `data_a`'));
      },
    );

    test('a feature importing a data package fails', () async {
      final run = await check({
        'modules/a/data/pubspec.yaml': pubspec('data_a'),
        'modules/a/feature/pubspec.yaml': pubspec(
          'feature_a',
          deps: ['data_a'],
        ),
        'modules/a/feature/lib/a.dart':
            "import 'package:data_a/data_a.dart';\n",
      });
      expectViolation(run, 'R3', 'modules/a/feature/lib/a.dart:1');
    });

    test(
      'a data package on its domain, data_core and its own api passes',
      () async {
        final run = await check({
          'platform/layers/data/pubspec.yaml': pubspec('data_core'),
          'modules/a/api/pubspec.yaml': pubspec('a_api'),
          'modules/a/domain/pubspec.yaml': pubspec('domain_a'),
          'modules/a/data/pubspec.yaml': pubspec(
            'data_a',
            deps: ['domain_a', 'data_core', 'a_api'],
          ),
          'modules/a/data/lib/a.dart':
              "import 'package:domain_a/domain_a.dart';\n"
              "import 'package:data_core/data_core.dart';\n"
              "import 'package:a_api/a_api.dart';\n",
        });
        expectClean(run, 'R3');
      },
    );

    test('a data package importing and declaring a feature fails', () async {
      final run = await check({
        'modules/a/feature/pubspec.yaml': pubspec('feature_a'),
        'modules/a/data/pubspec.yaml': pubspec('data_a', deps: ['feature_a']),
        'modules/a/data/lib/a.dart':
            "import 'package:feature_a/feature_a.dart';\n",
      });
      expectViolation(run, 'R3', 'modules/a/data/lib/a.dart:1');
      expect(run.output, contains('`data_a` imports feature `feature_a`'));
      expect(run.output, contains('modules/a/data/pubspec.yaml'));
      expect(run.output, contains('`data_a` declares feature `feature_a`'));
    });

    test("a data package depending on another module's data fails", () async {
      final run = await check({
        'modules/b/data/pubspec.yaml': pubspec('data_b'),
        'modules/a/data/pubspec.yaml': pubspec('data_a', deps: ['data_b']),
        'modules/a/data/lib/a.dart': "import 'package:data_b/data_b.dart';\n",
      });
      expectViolation(run, 'R3', 'modules/a/data/lib/a.dart:1');
      expect(run.output, contains("another module's data package `data_b`"));
      expect(run.output, contains('modules/a/data/pubspec.yaml'));
    });

    test(
      'a data package declaring a sibling data package of its module passes',
      () async {
        final run = await check({
          'modules/a/data/pubspec.yaml': pubspec('data_a'),
          'modules/a/data_local/pubspec.yaml': pubspec(
            'data_a_local',
            deps: ['data_a'],
          ),
        });
        expectClean(run, 'R3');
      },
    );
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

  group('R6 a file named like generated output carries the header', () {
    test('a generated file with its header raises nothing', () async {
      final run = await check({
        'platform/infra/foo/pubspec.yaml': pubspec('core_foo'),
        'platform/infra/foo/lib/foo.g.dart':
            '// GENERATED CODE - DO NOT MODIFY BY HAND\n',
      });
      expectClean(run, 'R6');
      expect(run.output, isNot(contains('generator header')));
    });

    test('a headerless file named like generated output fails', () async {
      final run = await check({
        'platform/infra/foo/pubspec.yaml': pubspec('core_foo'),
        'platform/infra/foo/lib/foo.g.dart': 'class Edited {}\n',
      });
      expectViolation(run, 'R6', 'platform/infra/foo/lib/foo.g.dart');
      expect(run.output, contains('generator header'));
    });

    test(
      'every conventional suffix needs the header, not just .g.dart',
      () async {
        final run = await check({
          'platform/infra/foo/pubspec.yaml': pubspec('core_foo'),
          'platform/infra/foo/lib/a.freezed.dart': 'class A {}\n',
          'platform/infra/foo/lib/b.config.dart': 'class B {}\n',
          'platform/infra/foo/lib/c.module.dart': 'class C {}\n',
        });
        expectViolation(run, 'R6', 'platform/infra/foo/lib/a.freezed.dart');
        expect(run.output, contains('platform/infra/foo/lib/b.config.dart'));
        expect(run.output, contains('platform/infra/foo/lib/c.module.dart'));
      },
    );

    test('a headerless lookalike is read by the other rules as hand-written '
        'code, so it cannot smuggle a violation past them', () async {
      final run = await check({
        'platform/infra/foo/pubspec.yaml': pubspec('core_foo'),
        'platform/infra/foo/lib/size_ext.g.dart': 'final gap = 16.w;\n',
        'platform/infra/foo/lib/size_ext.config.dart': 'final gap = 16.h;\n',
        'platform/infra/foo/lib/zz.freezed.dart':
            'void f() { debugPrint("x"); }\n',
      });
      expect(run, exitsWith(1));
      expect(run.output, contains('R7 — '));
      expect(run.output, contains('platform/infra/foo/lib/size_ext.g.dart:1'));
      expect(run.output, contains('size_ext.config.dart:1'));
      expect(run.output, contains('R19 — '));
      expect(run.output, contains('platform/infra/foo/lib/zz.freezed.dart:1'));
    });

    test(
      'a fake header must be the leading comment, not text further down',
      () async {
        final run = await check({
          'platform/infra/foo/pubspec.yaml': pubspec('core_foo'),
          'platform/infra/foo/lib/foo.g.dart':
              'class Edited {}\n// GENERATED CODE - DO NOT MODIFY BY HAND\n',
        });
        expectViolation(run, 'R6', 'platform/infra/foo/lib/foo.g.dart');
      },
    );

    test(
      'a hand-written file in gen/ or generated/ is not generated',
      () async {
        final run = await check({
          'platform/ui/kit/pubspec.yaml': pubspec('core_kit'),
          'platform/ui/kit/lib/src/gen/zz_gen.dart':
              'import \'package:feature_x/feature_x.dart\';\nfinal a = 16.w;\n',
          'platform/ui/kit/lib/src/generated/hand.dart':
              'import \'package:flutter/material.dart\';\n'
              'Widget w() { debugPrint("x"); return const SizedBox(width: 16); }\n',
          'modules/x/feature/pubspec.yaml': pubspec('feature_x'),
        });
        expect(run, exitsWith(1));
        expect(
          run.output,
          contains('platform/ui/kit/lib/src/gen/zz_gen.dart:1'),
        );
        expect(run.output, contains('R7 — '));
        expect(run.output, contains('R19 — '));
        expect(run.output, contains('R20 — '));
        expect(run.output, contains('R1 — '));
      },
    );

    test('real generator output in gen/ is skipped: flutter_gen by its header, '
        'gen-l10n by the l10n.yaml output-dir', () async {
      final run = await check({
        'platform/ui/kit/pubspec.yaml': pubspec('core_kit'),
        'platform/ui/kit/l10n.yaml':
            'arb-dir: assets/language\noutput-dir: lib/src/gen/language\n',
        'platform/ui/kit/lib/src/gen/assets.gen.dart':
            '// dart format width=80\n/// GENERATED CODE - DO NOT MODIFY BY HAND\n'
            'final a = 16.w;\n',
        'platform/ui/kit/lib/src/gen/language/app_localizations.dart':
            "import 'package:feature_x/feature_x.dart';\nfinal a = 16.w;\n",
      });
      expectClean(run, 'R7');
      expect(run.output, isNot(contains('R1 — ')));
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

    test(
      'a bare .w in a file that never imports core_responsive fails',
      () async {
        final run = await check({
          'platform/infra/foo/pubspec.yaml': pubspec('core_foo'),
          'platform/infra/foo/lib/foo.dart': 'final gap = 16.w;\n',
        });
        expectViolation(run, 'R7', 'platform/infra/foo/lib/foo.dart:1');
      },
    );

    test('a module widget with a bare .sp fails; a string and a generated '
        'file do not', () async {
      final run = await check({
        'modules/foo/feature/pubspec.yaml': pubspec('feature_foo'),
        'modules/foo/feature/lib/a.dart': "const label = 'size 16.sp';\n",
        'modules/foo/feature/lib/a.g.dart':
            '// GENERATED CODE - DO NOT MODIFY BY HAND\nfinal gap = 16.w;\n',
      });
      expectClean(run, 'R7');
      final bad = await check({
        'modules/foo/feature/pubspec.yaml': pubspec('feature_foo'),
        'modules/foo/feature/lib/a.dart': 'final f = (2 + 1).sp;\n',
      });
      expectViolation(bad, 'R7', 'modules/foo/feature/lib/a.dart:1');
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

    group('every spelling of a throwing lookup', () {
      for (final spelling in const {
        'getIt.get<T>()': 'final foo = getIt.get<IFooContract>();',
        'getIt.getAll<T>()': 'final foo = getIt.getAll<IFooContract>();',
        'getIt.getAsync<T>()': 'final foo = getIt.getAsync<IFooContract>();',
        'GetIt.I<T>()': 'final foo = GetIt.I<IFooContract>();',
        'GetIt.instance<T>()': 'final foo = GetIt.instance<IFooContract>();',
        'GetIt.instance.get<T>()':
            'final foo = GetIt.instance.get<IFooContract>();',
        'a type argument on the next line':
            'final foo = getIt<\n  IFooContract\n>();',
        'a spaced type argument': 'final foo = getIt < IFooContract > ();',
        'an untyped getIt() assigned to a declared type':
            'final IFooContract foo = getIt();',
        'an untyped getIt.get() assigned to a declared type':
            'IFooContract foo = getIt.get();',
      }.entries) {
        test('${spelling.key} fails', () async {
          final run = await check(contractFixture(spelling.value));
          expect(run, exitsWith(1));
          expect(run.output, contains('R8 — '));
          expect(
            run.output,
            contains('platform/shell/app_shell/lib/shell.dart:2'),
          );
        });
      }

      test('the optional spellings and a lookup in a comment pass', () async {
        final run = await check(
          contractFixture(
            '// final a = getIt<IFooContract>();\n'
            '/* getIt.get<IFooContract>() */\n'
            "const s = 'getIt<IFooContract>()';\n"
            'final b = getItOrNull<IFooContract>();\n'
            'final c = getAllOrEmpty<IFooContract>();\n'
            'final IFooContract? d = getItOrNull();',
          ),
        );
        expectClean(run, 'R8');
      });

      test('a lookup of a contract nobody removes passes', () async {
        final run = await check(
          contractFixture('final foo = getIt.get<SomethingElse>();'),
        );
        expectClean(run, 'R8');
      });
    });

    group('a non-module injectable that requires a module-owned contract', () {
      Map<String, String> injected(String cls) => {
        ...contractFixture('final foo = getItOrNull<IFooContract>();'),
        'platform/shell/app_shell/pubspec.yaml': pubspec(
          'platform_app_shell',
          deps: ['core_di', 'injectable'],
        ),
        'platform/shell/app_shell/lib/needy.dart':
            "import 'package:core_di/core_di.dart';\n"
            "import 'package:injectable/injectable.dart';\n"
            '$cls\n',
      };

      test('a required field-formal parameter fails', () async {
        final run = await check(
          injected(
            '@lazySingleton\n'
            'class Needy {\n'
            '  Needy(this._foo);\n'
            '  final IFooContract _foo;\n'
            '}',
          ),
        );
        expectViolation(
          run,
          'R8',
          'platform/shell/app_shell/lib/needy.dart:5',
        );
        expect(run.output, contains('required constructor parameter'));
      });

      test('a required typed parameter on an @injectable fails', () async {
        final run = await check(
          injected(
            '@injectable\n'
            'class Needy {\n'
            '  Needy(IFooContract foo, {required int other});\n'
            '}',
          ),
        );
        expect(run, exitsWith(1));
        expect(run.output, contains('R8 — '));
      });

      test('a nullable, a factoryParam and a plain class pass', () async {
        final run = await check(
          injected(
            '@injectable\n'
            'class A {\n'
            '  A(this._foo);\n'
            '  final IFooContract? _foo;\n'
            '}\n'
            '@injectable\n'
            'class B {\n'
            '  B(@factoryParam IFooContract? foo);\n'
            '}\n'
            '@injectable\n'
            'class C {\n'
            '  C(@factoryParam IFooContract foo);\n'
            '}\n'
            'class D {\n'
            '  D(IFooContract foo);\n'
            '}\n'
            '@injectable\n'
            'class E {\n'
            '  E(String name) : _gate = IFooContract.of(name);\n'
            '  final Object _gate;\n'
            '}',
          ),
        );
        expectClean(run, 'R8');
      });

      test('the owning module may inject its own contract', () async {
        final run = await check({
          ...contractFixture('final foo = getItOrNull<IFooContract>();'),
          'modules/foo/feature/lib/needy.dart':
              "import 'package:core_di/core_di.dart';\n"
              'class Needy {\n'
              '  Needy(this._foo);\n'
              '  final IFooContract _foo;\n'
              '}\n',
        });
        expectClean(run, 'R8');
      });
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

    for (final dep in ['dio', 'retrofit', 'http', 'drift', 'go_router']) {
      test('platform_kernel declaring and importing $dep fails', () async {
        final run = await check({
          'platform/foundation/kernel/pubspec.yaml': pubspec(
            'platform_kernel',
            deps: [dep],
          ),
          'platform/foundation/kernel/lib/k.dart':
              "import 'package:$dep/$dep.dart';\n",
        });
        expectViolation(run, 'R9', 'platform/foundation/kernel/lib/k.dart:1');
        expect(run.output, contains('platform/foundation/kernel/pubspec.yaml'));
      });
    }

    test(
      'a hosted Flutter plugin in the kernel fails, pure Dart passes',
      () async {
        final hosted = hostedPackages({
          'pure_helper': 'name: pure_helper\ndependencies:\n  path: any\n',
          'fancy_plugin':
              'name: fancy_plugin\nflutter:\n  plugin:\n'
              '    platforms:\n      android:\n        package: x\n',
        });
        final clean = await check({
          ...hosted,
          'platform/foundation/kernel/pubspec.yaml': pubspec(
            'platform_kernel',
            deps: ['pure_helper'],
          ),
          'platform/foundation/kernel/lib/k.dart':
              "import 'package:pure_helper/pure_helper.dart';\n",
        });
        expectClean(clean, 'R9');

        final run = await check({
          ...hosted,
          'platform/foundation/kernel/pubspec.yaml': pubspec(
            'platform_kernel',
            deps: ['fancy_plugin'],
          ),
          'platform/foundation/kernel/lib/k.dart':
              "import 'package:fancy_plugin/fancy_plugin.dart';\n",
        });
        expectViolation(run, 'R9', 'platform/foundation/kernel/lib/k.dart:1');
        expect(run.output, contains('platform/foundation/kernel/pubspec.yaml'));
        expect(run.output, contains('a Flutter plugin'));
      },
    );

    test(
      'a dependency that reaches the Flutter SDK through another fails',
      () async {
        final run = await check({
          ...hostedPackages({
            'wrapper': 'name: wrapper\ndependencies:\n  inner: any\n',
            'inner':
                'name: inner\ndependencies:\n  flutter:\n'
                '    sdk: flutter\n',
          }),
          'platform/foundation/kernel/pubspec.yaml': pubspec(
            'platform_kernel',
            deps: ['wrapper'],
          ),
        });
        expectViolation(run, 'R9', 'platform/foundation/kernel/pubspec.yaml');
        expect(run.output, contains('depends on the Flutter-bound `flutter`'));
      },
    );

    test('a workspace package with a Flutter SDK dependency fails', () async {
      final run = await check({
        'platform/foundation/common/pubspec.yaml': pubspec(
          'core_common',
          deps: ['flutter'],
        ),
        'platform/foundation/kernel/pubspec.yaml': pubspec(
          'platform_kernel',
          deps: ['core_common'],
        ),
      });
      expectViolation(run, 'R9', 'platform/foundation/kernel/pubspec.yaml');
      expect(run.output, contains('declares `core_common`'));
    });

    test('a *_contracts package is not in the pure tier any more', () async {
      final run = await check({
        'platform/foundation/contracts/pubspec.yaml': pubspec(
          'core_contracts',
          deps: ['flutter'],
        ),
      });
      expectClean(run, 'R9');
    });
  });

  group('R10 the app shell composes modules, it does not import them', () {
    Map<String, String> app(String mainImport) => {
      'modules/foo/feature/pubspec.yaml': pubspec('feature_foo'),
      'modules/auth/data/pubspec.yaml': pubspec('data_auth'),
      'platform/layers/domain/pubspec.yaml': pubspec('domain_core'),
      'platform/layers/data/pubspec.yaml': pubspec(
        'data_core',
        deps: ['domain_core'],
      ),
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

    test(
      'an app test importing a module fails, a platform import passes',
      () async {
        final clean = await check({
          ...app("import 'dart:async';\n"),
          'apps/demo/test/boot_test.dart':
              "import 'package:flutter_test/flutter_test.dart';\n"
              "import 'package:domain_core/domain_core.dart';\n"
              "import 'package:data_core/data_core.dart';\n",
        });
        expectClean(clean, 'R10');

        final run = await check({
          ...app("import 'dart:async';\n"),
          'apps/demo/test/boot_test.dart':
              "import 'package:feature_foo/feature_foo.dart';\n",
          'apps/demo/test/helpers/data_test.dart':
              "import 'package:data_auth/data_auth.dart';\n",
        });
        expectViolation(run, 'R10', 'apps/demo/test/boot_test.dart:1');
        expect(run.output, contains('apps/demo/test/helpers/data_test.dart:1'));
      },
    );

    test('an injection.dart under test/ is not the composition root', () async {
      final run = await check({
        ...app("import 'dart:async';\n"),
        'apps/demo/test/injection.dart':
            "import 'package:feature_foo/feature_foo.dart';\n",
      });
      expectViolation(run, 'R10', 'apps/demo/test/injection.dart:1');
    });

    test(
      'an injection.dart anywhere but lib/di/ is not the composition root',
      () async {
        final run = await check({
          ...app("import 'dart:async';\n"),
          'apps/demo/lib/other/injection.dart':
              "import 'package:feature_foo/feature_foo.dart';\n",
          'apps/demo/lib/injection.dart':
              "import 'package:feature_foo/feature_foo.dart';\n",
        });
        expectViolation(run, 'R10', 'apps/demo/lib/other/injection.dart:1');
        expect(run.output, contains('apps/demo/lib/injection.dart:1'));
        expect(
          run.output,
          isNot(contains('apps/demo/lib/di/injection.dart:1')),
        );
      },
    );

    test(
      'integration_test/, test_driver/, tool/ and bin/ are scanned too',
      () async {
        const naming = "import 'package:feature_foo/feature_foo.dart';\n";
        final run = await check({
          ...app("import 'dart:async';\n"),
          'apps/demo/integration_test/app_test.dart': naming,
          'apps/demo/test_driver/x.dart': naming,
          'apps/demo/tool/x.dart': naming,
          'apps/demo/bin/x.dart': naming,
        });
        expectViolation(
          run,
          'R10',
          'apps/demo/integration_test/app_test.dart:1',
        );
        expect(run.output, contains('apps/demo/test_driver/x.dart:1'));
        expect(run.output, contains('apps/demo/tool/x.dart:1'));
        expect(run.output, contains('apps/demo/bin/x.dart:1'));
      },
    );

    test('a generated file, build/ and .dart_tool/ are not scanned', () async {
      const naming = "import 'package:feature_foo/feature_foo.dart';\n";
      final run = await check({
        ...app("import 'dart:async';\n"),
        'apps/demo/lib/di/injection.config.dart':
            '// GENERATED CODE - DO NOT MODIFY BY HAND\n$naming',
        'apps/demo/build/x.dart': naming,
        'apps/demo/.dart_tool/x.dart': naming,
      });
      expectClean(run, 'R10');
    });

    test(
      'a hosted package named like a module is not a module package',
      () async {
        final run = await check({
          ...app(
            "import 'package:feature_discovery/feature_discovery.dart';\n",
          ),
          'apps/demo/pubspec.yaml': pubspec(
            'demo_app',
            deps: [
              'feature_foo',
              'feature_discovery',
              'data_table_2',
              'domain_driven',
              'core_extension',
              'billing_api',
            ],
          ),
          'apps/demo/lib/b.dart':
              "import 'package:data_table_2/data_table_2.dart';\n"
              "import 'package:domain_driven/x.dart';\n"
              "import 'package:core_extension/x.dart';\n"
              "import 'package:billing_api/billing_api.dart';\n",
        });
        expectClean(run, 'R10');
      },
    );

    test('a custom package under modules/ is a module package too', () async {
      final run = await check({
        ...app("import 'package:zed_shared/zed_shared.dart';\n"),
        'modules/zed/shared/pubspec.yaml': pubspec('zed_shared'),
      });
      expectViolation(run, 'R10', 'apps/demo/lib/main.dart:1');
    });

    test('conditional-import configurations and the missing-space spelling '
        'are read', () async {
      final run = await check({
        ...app(
          "import 'stub.dart' if (dart.library.io) "
          "'package:feature_foo/feature_foo.dart';\n",
        ),
        'apps/demo/lib/b.dart':
            "import'package:feature_foo/feature_foo.dart';\n",
        'apps/demo/lib/c.dart': "import 'dart:async'; import 'package:feature_foo/feature_foo.dart';\n",
      });
      expectViolation(run, 'R10', 'apps/demo/lib/main.dart:1');
      expect(run.output, contains('apps/demo/lib/b.dart:1'));
      expect(run.output, contains('apps/demo/lib/c.dart:1'));
    });

    test('a directive-looking line in a block comment or a string is not '
        'an import', () async {
      final run = await check({
        ...app(
          "/*\nimport 'package:feature_foo/feature_foo.dart';\n*/\n"
          "const t = '''\nimport 'package:feature_foo/feature_foo.dart';\n''';\n",
        ),
      });
      expectClean(run, 'R10');
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

    test('a platform group declaring a modules/ package fails', () async {
      final run = await check({
        ...dag(),
        'modules/auth/feature/pubspec.yaml': pubspec('feature_auth'),
        'platform/layers/data/pubspec.yaml': pubspec(
          'data_core',
          deps: ['platform_kernel', 'domain_core', 'feature_auth'],
        ),
      });
      expectViolation(run, 'R11', 'platform/layers/data/pubspec.yaml');
      expect(run.output, contains('No platform group may reach a module'));
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
              '/// Mentioning ignore_for_file: or ignore: mid-sentence is fine.\n'
              '// why // ignore: x is prose, not a suppression\n'
              '/* ignore: unused_import */\n'
              '// IGNORE: unused_import\n'
              '/// ignore_for_file: not honoured in a doc comment\n'
              "const tip = '// ignore: not a comment';\n"
              "const t2 = '''\n// ignore_for_file: template text\n''';\n",
          'platform/infra/foo/lib/foo.g.dart':
              '// GENERATED CODE - DO NOT MODIFY BY HAND\n'
              '// ignore_for_file: type=lint\n',
          'platform/infra/foo/lib/src/gen/assets.dart':
              '// GENERATED CODE - DO NOT MODIFY BY HAND\n'
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

    test(
      'the analyzer honours /// ignore: and //// ignore: too, so they fail',
      () async {
        final run = await check({
          'platform/infra/foo/pubspec.yaml': pubspec('core_foo'),
          'platform/infra/foo/lib/a.dart':
              '/// ignore: unused_import\nimport \'dart:async\';\n',
          'platform/infra/foo/lib/b.dart':
              '//// ignore: unused_import\nimport \'dart:async\';\n',
          'platform/infra/foo/lib/c.dart':
              '//ignore: unused_import\nimport \'dart:async\';\n',
          'platform/infra/foo/lib/d.dart':
              'import \'dart:async\'; // ignore: unused_import\n',
          'platform/infra/foo/lib/e.dart': '// ignore_for_file: type=lint\n',
        });
        expectViolation(run, 'R13', 'platform/infra/foo/lib/a.dart:1');
        for (final f in ['b', 'c', 'd', 'e']) {
          expect(run.output, contains('platform/infra/foo/lib/$f.dart:1'));
        }
      },
    );

    test(
      'a generated file under gen/ without a header is not exempt',
      () async {
        final run = await check({
          'platform/infra/foo/pubspec.yaml': pubspec('core_foo'),
          'platform/infra/foo/lib/src/gen/hand.dart':
              '// ignore_for_file: type=lint\n',
        });
        expectViolation(
          run,
          'R13',
          'platform/infra/foo/lib/src/gen/hand.dart:1',
        );
      },
    );

    test('the root analysis_options.yaml passes', () async {
      final run = await check({
        'analysis_options.yaml':
            'include: package:flutter_lints/flutter.yaml\n',
        'platform/infra/foo/pubspec.yaml': pubspec('core_foo'),
      });
      expectClean(run, 'R13');
    });

    test('a package-local analysis_options.yaml fails', () async {
      final run = await check({
        'analysis_options.yaml':
            'include: package:flutter_lints/flutter.yaml\n',
        'platform/infra/foo/pubspec.yaml': pubspec('core_foo'),
        'platform/infra/foo/analysis_options.yaml':
            'linter:\n  rules:\n    avoid_print: false\n',
        'apps/demo/analysis_options.yaml':
            'include: ../../analysis_options.yaml\n',
      });
      expectViolation(run, 'R13', 'platform/infra/foo/analysis_options.yaml');
      expect(run.output, contains('apps/demo/analysis_options.yaml'));
      expect(run.output, contains('package-local analysis_options.yaml'));
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

    test('a datasources/ folder under apps/ fails', () async {
      final run = await check({
        'apps/demo/app_manifest.yaml': 'app:\n  id: demo\n',
        'apps/demo/pubspec.yaml': pubspec('demo_app'),
        'apps/demo/lib/datasources/x.dart': '',
      });
      expectViolation(run, 'R14', 'apps/demo/lib/datasources');
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

  group('R16 the shell catalog is complete', () {
    const catalogPath =
        'platform/shell/app_shell/lib/src/utils/shell_contract_constants.dart';

    /// A catalog source with one row per type in [types].
    String catalog(List<String> types) {
      final rows = [
        for (final t in types)
          'ShellContract<$t>(\n'
              "  id: '${t.toLowerCase()}',\n"
              '  need: ShellNeed.optional,\n'
              '  cardinality: ContractCardinality.one,\n'
              "  consumer: 'a.dart:1',\n"
              "  whenAbsent: 'nothing',\n"
              '),',
      ];
      return 'const List<ShellContract<Object>> SHELL_CONTRACTS = [\n'
          '${rows.join('\n')}\n];\n';
    }

    /// `IFooContract` is implemented only in `modules/foo`; `IBarContract` by
    /// nobody (an app brings it). The shell package resolves [lookup].
    Map<String, String> shellFixture({
      required List<String> rows,
      String lookup = 'final foo = getItOrNull<IFooContract>();',
      Map<String, String> extra = const {},
    }) => {
      'platform/foundation/contracts/pubspec.yaml': pubspec('core_di'),
      'platform/foundation/contracts/lib/contracts.dart':
          'abstract class IFooContract {}\n'
          'abstract class IBarContract {}\n',
      'modules/foo/feature/pubspec.yaml': pubspec(
        'feature_foo',
        deps: ['core_di'],
      ),
      'modules/foo/feature/lib/foo.dart':
          'class FooImpl implements IFooContract {}\n',
      'platform/shell/app_shell/pubspec.yaml': pubspec(
        'platform_app_shell',
        deps: ['core_di'],
      ),
      catalogPath: catalog(rows),
      'platform/shell/app_shell/lib/shell.dart':
          "import 'package:core_di/core_di.dart';\n$lookup\n",
      ...extra,
    };

    test('a module-implemented contract with a catalog row passes', () async {
      final run = await check(shellFixture(rows: ['IFooContract']));
      expectClean(run, 'R16');
    });

    test('an optional lookup with no row fails, naming the module', () async {
      final run = await check(shellFixture(rows: ['IBarContract']));
      expectViolation(run, 'R16', 'platform/shell/app_shell/lib/shell.dart:2');
      expect(run.output, contains('`IFooContract`'));
      expect(run.output, contains('implemented only in modules/foo'));
      expect(run.output, contains('ShellContract<IFooContract>'));
    });

    test('a lookup of a contract nobody registers needs a row too', () async {
      final run = await check(
        shellFixture(
          rows: ['IFooContract'],
          lookup: 'final bar = getAllOrEmpty<IBarContract>();',
        ),
      );
      expectViolation(run, 'R16', 'platform/shell/app_shell/lib/shell.dart:2');
      expect(run.output, contains('No package registers it'));
    });

    test('a lookup of a type that is not a contract passes', () async {
      final run = await check(
        shellFixture(
          rows: ['IFooContract'],
          lookup: 'final hooks = getItOrNull<ShellHooks>();',
          extra: {
            'platform/shell/app_shell/lib/hooks.dart': 'class ShellHooks {}\n',
          },
        ),
      );
      expectClean(run, 'R16');
    });

    test('a lookup in a comment or a string passes', () async {
      final run = await check(
        shellFixture(
          rows: ['IFooContract'],
          lookup:
              '// getItOrNull<IBarContract>()\n'
              "const s = 'getItOrNull<IBarContract>()';",
        ),
      );
      expectClean(run, 'R16');
    });

    test('an uncatalogued lookup outside platform/ is not the shell', () async {
      final run = await check(
        shellFixture(
          rows: ['IFooContract'],
          extra: {
            'modules/foo/feature/lib/bar.dart':
                'final bar = getItOrNull<IBarContract>();\n',
          },
        ),
      );
      expectClean(run, 'R16');
    });

    test('a row for a type no package declares fails', () async {
      final run = await check(
        shellFixture(rows: ['IFooContract', 'IGoneContract']),
      );
      expectViolation(run, 'R16', catalogPath);
      expect(run.output, contains('`ShellContract<IGoneContract>`'));
    });

    test('a catalog row the parser cannot read fails', () async {
      final run = await check(
        shellFixture(
          rows: ['IFooContract'],
          extra: {
            catalogPath:
                'const SHELL_CONTRACTS = [\n'
                'ShellContract<IFooContract>(id: 1),\n'
                '];\n',
          },
        ),
      );
      expectViolation(run, 'R16', catalogPath);
      expect(run.output, contains('cannot be read'));
    });

    test('a workspace with no catalog is not asked for one', () async {
      final files = shellFixture(rows: ['IFooContract'])..remove(catalogPath);
      final run = await check(files);
      expectClean(run, 'R16');
    });
  });

  group('R17 platform forks are an app decision', () {
    const resolver =
        'platform/foundation/common/lib/src/config/platform_resolver.dart';

    Map<String, String> forkFixture(Map<String, String> files) => {
      'platform/foundation/common/pubspec.yaml': pubspec('core_common'),
      'modules/a/feature/pubspec.yaml': pubspec('feature_a'),
      'apps/demo/pubspec.yaml': pubspec('demo_app'),
      ...files,
    };

    test('the resolver may fork, and a fork named in a comment or string is '
        'not one', () async {
      final run = await check(
        forkFixture({
          resolver:
              "import 'package:flutter/foundation.dart';\n"
              'final web = kIsWeb;\n'
              'final target = defaultTargetPlatform;\n',
          'modules/a/feature/lib/a.dart':
              '/// Not `kIsWeb`, not Platform.isIOS.\n'
              "const s = 'Platform.isAndroid';\n",
        }),
      );
      expectClean(run, 'R17');
    });

    test('a fork in a test, or outside lib/, is not read', () async {
      final run = await check(
        forkFixture({
          'modules/a/feature/test/a_test.dart': 'final w = kIsWeb;\n',
          'modules/a/feature/tool/x.dart': 'final w = kIsWeb;\n',
        }),
      );
      expectClean(run, 'R17');
    });

    for (final fork in [
      'Platform.isAndroid',
      'Platform.isIOS',
      'Platform.operatingSystem',
      'kIsWeb',
      'defaultTargetPlatform',
      'TargetPlatform.iOS',
    ]) {
      test('$fork in a feature fails, naming the file and the line', () async {
        final run = await check(
          forkFixture({
            'modules/a/feature/lib/a.dart':
                "import 'dart:io';\nfinal here = $fork;\n",
          }),
        );
        expectViolation(run, 'R17', 'modules/a/feature/lib/a.dart:2');
        expect(run.output, contains('`${fork.replaceAll(' ', '')}`'));
        expect(run.output, contains('PlatformFacts'));
      });
    }

    test('an app fork fails too', () async {
      final run = await check(
        forkFixture({'apps/demo/lib/main.dart': 'final w = kIsWeb;\n'}),
      );
      expectViolation(run, 'R17', 'apps/demo/lib/main.dart:1');
    });

    test('an allow-listed file that no longer forks fails', () async {
      final run = await check(
        forkFixture({resolver: 'AppPlatform resolveAppPlatform() => web;\n'}),
      );
      expectViolation(run, 'R17', resolver);
      expect(run.output, contains('no longer forks'));
    });

    test('an allow-listed file that is gone fails in the tree that owns '
        'the list, and is not asked for elsewhere', () async {
      // A fixture has none of the shipped files and is not asked for them.
      expectClean(await check(forkFixture({})), 'R17');

      // The tree that carries the list is: every entry must exist.
      final run = await check(
        forkFixture({
          'tools/arch_check/platform_forks.dart': '// the list lives here\n',
        }),
      );
      expectViolation(run, 'R17', resolver);
      expect(run.output, contains('does not exist'));
    });

    test('every shipped allow-list entry says why', () {
      expect(kPlatformForkAllowList, isNotEmpty);
      expect(allowListProblems(kPlatformForkAllowList), isEmpty);
    });

    test('an allow-list entry without a reason is itself a failure', () {
      expect(
        allowListProblems({'platform/a/lib/a.dart': '', 'b.dart': '  '}),
        hasLength(2),
      );
      expect(
        allowListProblems({'platform/a/lib/a.dart': 'TODO'}),
        hasLength(1),
      );
      expect(
        allowListProblems({
          'platform/a/lib/a.dart': 'dart:io Platform throws on the web',
        }),
        isEmpty,
      );
    });
  });

  group('R18 Bloc event handlers are async', () {
    Map<String, String> bloc(String body) => {
      'modules/foo/feature/pubspec.yaml': pubspec(
        'feature_foo',
        deps: ['bloc_state_management'],
      ),
      'modules/foo/feature/lib/foo_bloc.dart':
          "import 'package:bloc_state_management/bloc_state_management.dart';\n"
          'class FooBloc extends BaseBloc<Object, int> {\n'
          '$body\n'
          '}\n',
    };

    test('async tear-offs and async closures pass', () async {
      final run = await check(
        bloc(
          '  FooBloc() : super(0) {\n'
          '    on<A>(_onA);\n'
          '    on<B>(this._onB, transformer: sequential());\n'
          '    on<C>((event, emit) async {\n'
          '      emit(1);\n'
          '    });\n'
          '    on<D>((event, emit) async => emit(2));\n'
          '    on<List<int>>(\n'
          '      (event, emit) async {},\n'
          '    );\n'
          '    on<E>(_inherited);\n'
          '  }\n'
          '  Future<void> _onA(A event, Emitter<int> emit) async {}\n'
          '  @override\n'
          '  Future<void> _onB(B event, Emitter<int> emit) async {\n'
          '    emit(3);\n'
          '  }\n',
        ),
      );
      expectClean(run, 'R18');
    });

    test('a sync block closure fails', () async {
      final run = await check(
        bloc(
          '  FooBloc() : super(0) {\n'
          '    on<A>((event, emit) {\n'
          '      _load(emit);\n'
          '    });\n'
          '  }\n',
        ),
      );
      expectViolation(run, 'R18', 'modules/foo/feature/lib/foo_bloc.dart:4');
      expect(run.output, contains('not `async`'));
    });

    test('a sync arrow closure fails', () async {
      final run = await check(
        bloc(
          '  FooBloc() : super(0) {\n'
          '    on<A>((event, emit) => _load(emit));\n'
          '  }\n',
        ),
      );
      expectViolation(run, 'R18', 'modules/foo/feature/lib/foo_bloc.dart:4');
    });

    test('a tear-off of a method that is not async fails', () async {
      final run = await check(
        bloc(
          '  FooBloc() : super(0) {\n'
          '    on<A>(_onA);\n'
          '  }\n'
          '  Future<void> _onA(A event, Emitter<int> emit) => _load(emit);\n',
        ),
      );
      expectViolation(run, 'R18', 'modules/foo/feature/lib/foo_bloc.dart:4');
      expect(run.output, contains('`_onA` is not declared `async`'));
    });

    test('a tear-off of a void method fails', () async {
      final run = await check(
        bloc(
          '  FooBloc() : super(0) {\n'
          '    on<A>(_onA);\n'
          '  }\n'
          '  void _onA(A event, Emitter<int> emit) {}\n',
        ),
      );
      expect(run, exitsWith(1));
      expect(run.output, contains('R18 — '));
    });

    test('an async method that does not return Future<void> fails', () async {
      final run = await check(
        bloc(
          '  FooBloc() : super(0) {\n'
          '    on<A>(_onA);\n'
          '  }\n'
          '  Future<int> _onA(A event, Emitter<int> emit) async => 1;\n',
        ),
      );
      expect(run, exitsWith(1));
      expect(run.output, contains('not `Future<void>`'));
    });

    test('the module generator\'s bloc template is compliant', () async {
      final template = File(
        '$repoRoot/tools/module_generator/templates/feature/bloc/'
        'bloc.dart.mustache',
      ).readAsStringSync();
      final rendered = template
          .replaceAll('{{pascalNameInput}}', 'Notes')
          .replaceAll('{{snakeNameInput}}', 'notes');
      final run = await check({
        'modules/notes/feature/pubspec.yaml': pubspec(
          'feature_notes',
          deps: [
            'bloc_state_management',
            'domain_core',
            'freezed_annotation',
            'injectable',
          ],
        ),
        'modules/notes/feature/lib/notes_bloc.dart': rendered,
      });
      expectClean(run, 'R18');
      // The same template with its handler stripped of `async` is caught: the
      // check is reading the template's real handler, not passing vacuously.
      final broken = await check({
        'modules/notes/feature/pubspec.yaml': pubspec(
          'feature_notes',
          deps: [
            'bloc_state_management',
            'domain_core',
            'freezed_annotation',
            'injectable',
          ],
        ),
        'modules/notes/feature/lib/notes_bloc.dart': rendered.replaceFirst(
          ') async => emitResult(',
          ') => emitResult(',
        ),
      });
      expectViolation(
        broken,
        'R18',
        'modules/notes/feature/lib/notes_bloc.dart:21',
      );
    });

    test('an on<> in a comment or another object is not a handler', () async {
      final run = await check(
        bloc(
          '  // on<A>((event, emit) {});\n'
          '  void other(Stream<int> s) => s.on<int>((e) {});\n'
          '  T pick<T>(Object o) => o.extension<T>();\n',
        ),
      );
      expectClean(run, 'R18');
    });
  });

  group('R19 runtime diagnostics go through DynamicLogger', () {
    test('DynamicLogger, a doc-comment example and a string pass', () async {
      final run = await check({
        'platform/infra/foo/pubspec.yaml': pubspec('core_foo'),
        'platform/infra/foo/lib/foo.dart':
            '/// Example: `print(x)`.\n'
            "const hint = 'call print(x) to see it';\n"
            'void log(Object m) => DynamicLogger.log(m);\n'
            'void debugPrintThrottled(String m) {}\n'
            'class Sink { void print(Object o) {} }\n',
      });
      expectClean(run, 'R19');
    });

    for (final call in const [
      'debugPrint("x");',
      'debugPrintStack(stackTrace: s);',
      'print("x");',
    ]) {
      test('$call in a platform lib fails', () async {
        final run = await check({
          'platform/infra/foo/pubspec.yaml': pubspec('core_foo'),
          'platform/infra/foo/lib/foo.dart': 'void f(s) {\n  $call\n}\n',
        });
        expectViolation(run, 'R19', 'platform/infra/foo/lib/foo.dart:2');
      });
    }

    test('print in a module lib fails; in test/ it passes', () async {
      final run = await check({
        'modules/foo/feature/pubspec.yaml': pubspec('feature_foo'),
        'modules/foo/feature/lib/foo.dart': 'void f() => print(1);\n',
        'modules/foo/feature/test/foo_test.dart': 'void main() => print(1);\n',
      });
      expectViolation(run, 'R19', 'modules/foo/feature/lib/foo.dart:1');
      expect(run.output, isNot(contains('foo_test.dart')));
    });

    test('a tool under tools/ may print', () async {
      final run = await check({
        'tools/pubspec.yaml': pubspec('tools'),
        'tools/lib/t.dart': 'void f() => print(1);\n',
      });
      expectClean(run, 'R19');
    });
  });

  group('R20 no raw numeric literals for layout and paint', () {
    Future<ToolRun> widget(String body, {String file = 'widgets/box.dart'}) {
      return check({
        'platform/ui/foo/pubspec.yaml': pubspec('core_foo'),
        'platform/ui/foo/lib/$file': 'final w = $body;\n',
      });
    }

    test('context-scaled values, tokens and zero pass', () async {
      final run = await check({
        'platform/ui/foo/pubspec.yaml': pubspec('core_foo'),
        'platform/ui/foo/lib/box.dart':
            'final a = SizedBox(width: context.w(8), height: AppSpacing.md);\n'
            'final b = EdgeInsets.symmetric(horizontal: context.w(16));\n'
            'final c = const EdgeInsets.all(0);\n'
            'final d = BorderRadius.circular(context.r(8));\n'
            'final e = TextStyle(fontSize: context.sp(14));\n'
            'final f = Offset(0, context.h(4));\n'
            'final g = SizedBox(child: x, width: double.infinity);\n'
            'final h = Radius.circular(AppRadius.md);\n'
            'final i = SizedBox.shrink();\n'
            "final j = 'SizedBox(width: 8)';\n"
            '// final k = EdgeInsets.all(8);\n',
      });
      expectClean(run, 'R20');
    });

    for (final bad in const {
      'SizedBox(width: 8)': 'SizedBox(width: 8)',
      'SizedBox(child: c, height: 12.5)': 'SizedBox(child: c, height: 12.5)',
      'SizedBox.square(dimension: 24)': 'SizedBox.square(dimension: 24)',
      'EdgeInsets.all(16)': 'EdgeInsets.all(16)',
      'EdgeInsets.symmetric(horizontal: 4)':
          'EdgeInsets.symmetric(horizontal: 4)',
      'EdgeInsets.only(left: context.w(1), top: 8)':
          'EdgeInsets.only(left: context.w(1), top: 8)',
      'EdgeInsets.fromLTRB(1, 2, 3, 4)': 'EdgeInsets.fromLTRB(1, 2, 3, 4)',
      'EdgeInsetsDirectional.only(start: 8)':
          'EdgeInsetsDirectional.only(start: 8)',
      'TextStyle(fontSize: 14)': 'TextStyle(fontSize: 14)',
      'BorderRadius.circular(8)': 'BorderRadius.circular(8)',
      'Radius.circular(8)': 'Radius.circular(8)',
      'BoxShadow(blurRadius: 4)': 'BoxShadow(blurRadius: 4)',
      'CircularProgressIndicator(strokeWidth: 2)':
          'CircularProgressIndicator(strokeWidth: 2)',
      'Offset(4, 0)': 'Offset(4, 0)',
    }.entries) {
      test('${bad.key} fails', () async {
        final run = await widget(bad.value);
        expectViolation(run, 'R20', 'platform/ui/foo/lib/widgets/box.dart:1');
      });
    }

    test('a multi-line call is found at the offending argument', () async {
      final run = await check({
        'platform/ui/foo/pubspec.yaml': pubspec('core_foo'),
        'platform/ui/foo/lib/box.dart':
            'final a = EdgeInsets.symmetric(\n'
            '  horizontal: context.w(8),\n'
            '  vertical: 8,\n'
            ');\n',
      });
      expectViolation(run, 'R20', 'platform/ui/foo/lib/box.dart:3');
    });

    test('the same literals under styles/ and utils/ pass', () async {
      final run = await check({
        'platform/ui/foo/pubspec.yaml': pubspec('core_foo'),
        'platform/ui/foo/lib/src/styles/shadows.dart':
            'final a = BoxShadow(blurRadius: 4, offset: Offset(0, 2));\n',
        'platform/ui/foo/lib/src/utils/consts.dart':
            'final a = EdgeInsets.all(16);\n',
      });
      expectClean(run, 'R20');
    });

    test('a generated file and a test pass; a module widget fails', () async {
      final run = await check({
        'modules/foo/feature/pubspec.yaml': pubspec('feature_foo'),
        'modules/foo/feature/lib/a.freezed.dart':
            '// GENERATED CODE - DO NOT MODIFY BY HAND\n'
            'final a = EdgeInsets.all(16);\n',
        'modules/foo/feature/test/a_test.dart':
            'final a = EdgeInsets.all(16);\n',
      });
      expectClean(run, 'R20');
      final bad = await check({
        'modules/foo/feature/pubspec.yaml': pubspec('feature_foo'),
        'modules/foo/feature/lib/page.dart': 'final a = EdgeInsets.all(16);\n',
      });
      expectViolation(bad, 'R20', 'modules/foo/feature/lib/page.dart:1');
    });
  });

  group('where the repository is cloned never changes the answer', () {
    /// A small but complete workspace: platform, one module, an app.
    Map<String, String> tree({String platformImport = ''}) => {
      'pubspec.yaml': 'name: ws\n',
      'platform/layers/domain/pubspec.yaml': pubspec('domain_core'),
      'platform/infra/network/pubspec.yaml': pubspec(
        'core_network',
        deps: [if (platformImport.isNotEmpty) 'feature_auth'],
      ),
      'platform/infra/network/lib/net.dart': 'final a = 1;\n$platformImport',
      'modules/auth/domain/pubspec.yaml': pubspec(
        'domain_auth',
        deps: ['domain_core'],
      ),
      'modules/auth/domain/lib/auth.dart':
          "import 'package:domain_core/domain_core.dart';\n",
      'modules/auth/feature/pubspec.yaml': pubspec(
        'feature_auth',
        deps: ['domain_auth'],
      ),
      'modules/auth/feature/lib/auth_page.dart':
          "import 'package:domain_auth/domain_auth.dart';\n",
      'apps/demo/app_manifest.yaml': 'app:\n  id: demo\n',
      'apps/demo/pubspec.yaml': pubspec('demo_app', deps: ['feature_auth']),
      'apps/demo/lib/di/injection.dart':
          "import 'package:feature_auth/feature_auth.dart';\n",
    };

    const bad = "import 'package:feature_auth/feature_auth.dart';\n";

    for (final nested in [
      'modules/repo',
      'gen/repo',
      'generated/repo',
      'platform/repo',
      'apps/modules/gen/generated/repo',
    ]) {
      test('a clean tree stays clean under $nested/', () async {
        final ws = TempWorkspace.create(tree(), nestedUnder: nested);
        final run = await tool.run(const [], workingDirectory: ws.root);
        expect(run, exitsWith(0));
        expect(run.output, contains('All architecture rules hold'));
      });

      test(
        'a platform -> feature import is still found under $nested/',
        () async {
          final ws = TempWorkspace.create(
            tree(platformImport: bad),
            nestedUnder: nested,
          );
          final run = await tool.run(const [], workingDirectory: ws.root);
          expectViolation(run, 'R1', 'platform/infra/network/lib/net.dart:2');
          // The generated-file test reads the path below the package, so the
          // hand-written file is scanned: R5 sees the undeclared import too.
          expect(run.output, isNot(contains('R16 — ')));
        },
      );

      test('the other source rules still fire under $nested/', () async {
        final ws = TempWorkspace.create({
          ...tree(),
          'platform/infra/network/lib/p.dart':
              'final a = 16.w;\nfinal b = getIt<AuthNavigator>();\n'
              'void f() { debugPrint("x"); }\n',
        }, nestedUnder: nested);
        final run = await tool.run(const [], workingDirectory: ws.root);
        expect(run, exitsWith(1));
        expect(run.output, contains('R7 — '));
        expect(run.output, contains('R19 — '));
        expect(run.output, contains('platform/infra/network/lib/p.dart:1'));
      });
    }
  });

  group('edges are classified by workspace location, not by name prefix', () {
    test('hosted packages named like a layer are third-party code', () async {
      final run = await check({
        'platform/ui/kit/pubspec.yaml': pubspec(
          'core_kit',
          deps: ['data_table_2', 'feature_discovery', 'domain_driven'],
        ),
        'platform/ui/kit/lib/k.dart':
            "import 'package:data_table_2/data_table_2.dart';\n"
            "import 'package:feature_discovery/feature_discovery.dart';\n",
        'modules/settings/feature/pubspec.yaml': pubspec(
          'feature_settings',
          deps: ['feature_discovery', 'data_table_2'],
        ),
        'modules/settings/feature/lib/s.dart':
            "import 'package:feature_discovery/feature_discovery.dart';\n"
            "import 'package:data_table_2/data_table_2.dart';\n",
        'modules/settings/data/pubspec.yaml': pubspec(
          'data_settings',
          deps: ['feature_discovery', 'data_table_2'],
        ),
        'modules/settings/domain/pubspec.yaml': pubspec(
          'domain_settings',
          deps: ['core_extension'],
        ),
        'modules/settings/api/pubspec.yaml': pubspec(
          'settings_api',
          deps: ['feature_discovery'],
        ),
      });
      for (final rule in ['R1', 'R2', 'R3']) {
        expect(run.output, isNot(contains('$rule — ')), reason: rule);
      }
    });

    test(
      'a workspace package is judged by its folder even when mis-named',
      () async {
        final run = await check({
          'modules/zed/domain/pubspec.yaml': pubspec('zed_domain'),
          'modules/zed/domain/lib/z.dart':
              "import 'package:flutter/material.dart';\n",
        });
        expectViolation(run, 'R2', 'modules/zed/domain/lib/z.dart:1');
        expect(run.output, contains('must be named `domain_zed`'));
      },
    );

    test(
      'a mis-named feature and data package still get the R3 line',
      () async {
        final run = await check({
          'modules/other/feature/pubspec.yaml': pubspec('feature_other'),
          'modules/other/data/pubspec.yaml': pubspec('data_other'),
          'modules/zed/feature/pubspec.yaml': pubspec(
            'zed_feature',
            deps: ['feature_other', 'data_other'],
          ),
          'modules/zed/feature/lib/z.dart':
              "import 'package:feature_other/feature_other.dart';\n",
          'modules/zed/data/pubspec.yaml': pubspec(
            'zed_data',
            deps: ['feature_other'],
          ),
        });
        expectViolation(run, 'R3', 'modules/zed/feature/lib/z.dart:1');
        expect(run.output, contains('imports another feature `feature_other`'));
        expect(run.output, contains('declares data package `data_other`'));
        expect(run.output, contains('`zed_data` declares feature'));
        // Not "platform must not reach modules": they are not platform.
        expect(run.output, isNot(contains('core package `zed_')));
        expect(run.output, contains('must be named `feature_zed`'));
        expect(run.output, contains('must be named `data_zed`'));
      },
    );

    test('the right names pass the naming check', () async {
      final run = await check({
        'modules/zed/domain/pubspec.yaml': pubspec('domain_zed'),
        'modules/zed/data/pubspec.yaml': pubspec('data_zed'),
        'modules/zed/feature/pubspec.yaml': pubspec('feature_zed'),
        'modules/zed/api/pubspec.yaml': pubspec('zed_api'),
        'modules/zed/shared/pubspec.yaml': pubspec('anything_goes'),
      });
      expectClean(run, 'R3');
    });

    test('R10 sees a custom package under modules/, R1 too', () async {
      final run = await check({
        'modules/zed/shared/pubspec.yaml': pubspec('zed_shared'),
        'platform/infra/foo/pubspec.yaml': pubspec(
          'core_foo',
          deps: ['zed_shared'],
        ),
        'platform/infra/foo/lib/f.dart':
            "import 'package:zed_shared/zed_shared.dart';\n",
      });
      expectViolation(run, 'R1', 'platform/infra/foo/lib/f.dart:1');
    });

    test("a feature or data package reaching another module's domain fails, "
        'its own passes', () async {
      final run = await check({
        'modules/cache/domain/pubspec.yaml': pubspec('domain_cache'),
        'modules/settings/domain/pubspec.yaml': pubspec('domain_settings'),
        'modules/settings/feature/pubspec.yaml': pubspec(
          'feature_settings',
          deps: ['domain_settings', 'domain_cache'],
        ),
        'modules/settings/feature/lib/s.dart':
            "import 'package:domain_settings/domain_settings.dart';\n"
            "import 'package:domain_cache/domain_cache.dart';\n",
        'modules/settings/data/pubspec.yaml': pubspec(
          'data_settings',
          deps: ['domain_settings', 'domain_cache'],
        ),
      });
      expectViolation(run, 'R3', 'modules/settings/feature/lib/s.dart:2');
      expect(run.output, isNot(contains('lib/s.dart:1\n')));
      expect(
        run.output,
        contains("`feature_settings` imports another module's domain package"),
      );
      expect(
        run.output,
        contains("`data_settings` declares another module's domain package"),
      );
    });

    test("another module's API is for features only, not for data", () async {
      final run = await check({
        'modules/auth/api/pubspec.yaml': pubspec('auth_api'),
        'modules/settings/feature/pubspec.yaml': pubspec(
          'feature_settings',
          deps: ['auth_api'],
        ),
        'modules/settings/data/pubspec.yaml': pubspec(
          'data_settings',
          deps: ['auth_api'],
        ),
      });
      expectViolation(run, 'R3', 'modules/settings/data/pubspec.yaml');
      expect(run.output, contains("another module's API package `auth_api`"));
      expect(run.output, isNot(contains('`feature_settings` declares')));
    });
  });

  group('dev dependencies and test imports are edges too', () {
    test('a platform package declaring or testing a module fails', () async {
      final run = await check({
        'modules/auth/feature/pubspec.yaml': pubspec('feature_auth'),
        'modules/auth/data/pubspec.yaml': pubspec('data_auth'),
        'platform/infra/network/pubspec.yaml': pubspec(
          'core_network',
          devDeps: ['feature_auth', 'data_auth'],
        ),
        'platform/infra/network/test/x_test.dart':
            "import 'package:feature_auth/feature_auth.dart';\n",
        'platform/infra/network/integration_test/y_test.dart':
            "import 'package:data_auth/data_auth.dart';\n",
      });
      expectViolation(run, 'R1', 'platform/infra/network/pubspec.yaml');
      expect(run.output, contains('declares under `dev_dependencies:`'));
      expect(run.output, contains('platform/infra/network/test/x_test.dart:1'));
      expect(
        run.output,
        contains('platform/infra/network/integration_test/y_test.dart:1'),
      );
    });

    test(
      'platform -> platform dev dependencies and tests stay exempt (R11)',
      () async {
        final run = await check({
          'platform/infra/storage/pubspec.yaml': pubspec('core_storage'),
          'platform/shell/app_shell/pubspec.yaml': pubspec(
            'platform_app_shell',
            devDeps: ['core_storage'],
          ),
          'platform/shell/app_shell/test/a_test.dart':
              "import 'package:core_storage/core_storage.dart';\n",
          'platform/infra/network/pubspec.yaml': pubspec(
            'core_network',
            devDeps: ['core_storage'],
          ),
        });
        expectClean(run, 'R1');
        expectClean(run, 'R11');
      },
    );

    test('a feature or data package declaring or testing the wrong module '
        'fails', () async {
      final run = await check({
        'modules/home/feature/pubspec.yaml': pubspec('feature_home'),
        'modules/cache/data/pubspec.yaml': pubspec('data_cache'),
        'modules/settings/feature/pubspec.yaml': pubspec(
          'feature_settings',
          devDeps: ['feature_home'],
        ),
        'modules/settings/feature/test/s_test.dart':
            "import 'package:feature_home/feature_home.dart';\n",
        'modules/auth/data/pubspec.yaml': pubspec(
          'data_auth',
          devDeps: ['data_cache'],
        ),
        'modules/auth/data/test/a_test.dart':
            "import 'package:data_cache/data_cache.dart';\n",
      });
      expectViolation(run, 'R3', 'modules/settings/feature/pubspec.yaml');
      expect(
        run.output,
        contains('modules/settings/feature/test/s_test.dart:1'),
      );
      expect(run.output, contains('modules/auth/data/pubspec.yaml'));
      expect(run.output, contains('modules/auth/data/test/a_test.dart:1'));
    });

    test('an API package with a dev dependency on a feature fails', () async {
      final run = await check({
        'modules/auth/feature/pubspec.yaml': pubspec('feature_auth'),
        'modules/auth/api/pubspec.yaml': pubspec(
          'auth_api',
          devDeps: ['feature_auth'],
        ),
      });
      expectViolation(run, 'R3', 'modules/auth/api/pubspec.yaml');
    });

    test(
      'a pure-Dart tier with a Flutter test dependency fails (R2, R9)',
      () async {
        final run = await check({
          'modules/x/domain/pubspec.yaml': pubspec(
            'domain_x',
            devDeps: ['flutter_test'],
          ),
          'modules/x/domain/test/x_test.dart':
              "import 'package:flutter_test/flutter_test.dart';\n",
          'platform/foundation/kernel/pubspec.yaml': pubspec(
            'platform_kernel',
            devDeps: ['flutter_test'],
          ),
          'platform/foundation/kernel/test/k_test.dart':
              "import 'package:flutter_test/flutter_test.dart';\n",
        });
        expectViolation(run, 'R2', 'modules/x/domain/pubspec.yaml');
        expect(run.output, contains('R9 — '));
        expect(run.output, contains('platform/foundation/kernel/pubspec.yaml'));
        expect(
          run.output,
          contains('platform/foundation/kernel/test/k_test.dart:1'),
        );
      },
    );

    test(
      'a test importing its own package or a pure-Dart one passes',
      () async {
        final run = await check({
          'modules/x/domain/pubspec.yaml': pubspec(
            'domain_x',
            devDeps: ['test'],
          ),
          'modules/x/domain/test/x_test.dart':
              "import 'package:test/test.dart';\n"
              "import 'package:domain_x/domain_x.dart';\n",
        });
        expectClean(run, 'R2');
      },
    );
  });

  group('imports are read from the lexer, not a line regex', () {
    /// A feature that must not import `feature_b`, written every way.
    Future<ToolRun> featureWith(String source) => check({
      'modules/b/feature/pubspec.yaml': pubspec('feature_b'),
      'modules/a/feature/pubspec.yaml': pubspec(
        'feature_a',
        deps: ['feature_b'],
      ),
      'modules/a/feature/lib/a.dart': source,
    });

    for (final entry in {
      'no space after import': "import'package:feature_b/feature_b.dart';\n",
      'a second directive on the line':
          "import 'dart:async'; import 'package:feature_b/feature_b.dart';\n",
      'a conditional configuration':
          "import 'stub.dart' if (dart.library.io) "
          "'package:feature_b/feature_b.dart';\n",
      'a second conditional configuration':
          "import 'stub.dart' if (dart.library.io) 'io.dart' "
          "if (dart.library.html) 'package:feature_b/feature_b.dart';\n",
      'an export': "export 'package:feature_b/feature_b.dart';\n",
      'a wrapped show clause':
          "import 'package:feature_b/feature_b.dart'\n    show B;\n",
      'a directive after a block comment':
          "/* x */ import 'package:feature_b/feature_b.dart';\n",
    }.entries) {
      test('${entry.key} is found (R3 imports)', () async {
        final run = await featureWith(entry.value);
        expectViolation(run, 'R3', 'modules/a/feature/lib/a.dart:1');
        expect(run.output, contains('`feature_a` imports another feature'));
      });
    }

    test(
      'a conditional configuration naming flutter fails in the domain',
      () async {
        final run = await check({
          'modules/x/domain/pubspec.yaml': pubspec('domain_x'),
          'modules/x/domain/lib/x.dart': "import 'stub.dart' if (dart.library.ui) 'package:flutter/material.dart';\n",
        });
        expectViolation(run, 'R2', 'modules/x/domain/lib/x.dart:1');
      },
    );

    test('and the kernel', () async {
      final run = await check({
        'platform/foundation/kernel/pubspec.yaml': pubspec('platform_kernel'),
        'platform/foundation/kernel/lib/k.dart': "import 'stub.dart' if (dart.library.html) 'package:dio/dio.dart';\n",
      });
      expectViolation(run, 'R9', 'platform/foundation/kernel/lib/k.dart:1');
    });

    for (final entry in {
      'a block comment': "/*\nimport 'package:feature_b/feature_b.dart';\n*/\n",
      'a triple-quoted string':
          "const t = '''\nimport 'package:feature_b/feature_b.dart';\n''';\n",
      'a doc comment':
          "/// import 'package:feature_b/feature_b.dart';\nconst a = 1;\n",
      'a line comment': "// import 'package:feature_b/feature_b.dart';\n",
      'a string': "const s = \"import 'package:feature_b/feature_b.dart';\";\n",
    }.entries) {
      test('${entry.key} is not an import', () async {
        final run = await check({
          'modules/b/feature/pubspec.yaml': pubspec('feature_b'),
          'modules/a/feature/pubspec.yaml': pubspec('feature_a'),
          'modules/a/feature/lib/a.dart': entry.value,
        });
        expectClean(run, 'R3');
        expect(run.output, isNot(contains('R5 — ')));
      });
    }
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

/// Pretends `pub get` resolved [pubspecs] (package name -> its pubspec text)
/// as hosted packages: a `.dart_tool/package_config.json` pointing at folders
/// the workspace walk never enters (hidden directories).
Map<String, String> hostedPackages(Map<String, String> pubspecs) => {
  '.dart_tool/package_config.json':
      '{"configVersion": 2, "packages": [${[
        for (final name in pubspecs.keys) '{"name": "$name", "rootUri": "../.hosted/$name", '
              '"packageUri": "lib/"}',
      ].join(', ')}]}',
  for (final entry in pubspecs.entries)
    '.hosted/${entry.key}/pubspec.yaml': entry.value,
};

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
