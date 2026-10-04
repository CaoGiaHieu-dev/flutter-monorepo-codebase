import 'dart:io';

import 'package:test/test.dart';

import 'support/tool_harness.dart';

/// `tools/code_review` — which files a review looks at.
///
/// `FileAnalyzer` / `FileService` / `GitHelper` read the current directory
/// and git, so they are driven through `support/code_review_probe.dart` as a
/// process in a throwaway workspace (a `Directory.current` change inside
/// `dart test` would leak into the other test files). Nothing here calls
/// Gemini.
void main() {
  late CompiledTool probe;
  setUpAll(() async {
    probe = await CompiledTool.compile(
      'tools/test/support/code_review_probe.dart',
    );
  });
  tearDownAll(() => probe.dispose());

  final hasGit = Process.runSync('git', ['--version']).exitCode == 0;
  final Object needsGit = hasGit ? false : 'git is not installed';

  /// A workspace root with sources of every kind the filters must tell apart.
  Map<String, String> sources() => {
    'pubspec.yaml': 'name: ws\nworkspace:\n  - apps/mobile\n',
    '.gitignore': 'ignored_by_git.dart\n',
    'apps/mobile/lib/main.dart': 'void main() {}\n',
    'apps/mobile/lib/main.g.dart': '// generated\n',
    'apps/mobile/lib/model.freezed.dart': '// generated\n',
    'apps/mobile/lib/firebase/firebase_options_dev.dart': '// per project\n',
    'apps/mobile/test/main_test.dart': '// test\n',
    'apps/mobile/pubspec.yaml': 'name: mobile\n',
    'modules/auth/feature/lib/pages/login_page.dart': 'class LoginPage {}\n',
    'modules/auth/feature/lib/routing/deep/auth_route.dart': 'class R {}\n',
    'modules/auth/feature/lib/src/gen/strings.dart': '// gen output\n',
    'modules/auth/feature/lib/test/helper.dart': '// under a /test/ segment\n',
    'modules/auth/feature/lib/ignored_by_git.dart': 'class Ignored {}\n',
    'modules/auth/feature/.dart_tool/x/lib/cache.dart': '// cache\n',
    'modules/auth/feature/build/lib/out.dart': '// build\n',
    'modules/auth/feature/pubspec.yaml':
        'name: feature_auth\ndependencies:\n  flutter:\n    sdk: flutter\n',
    'platform/core/lib/core.dart': 'class Core {}\n',
    'tools/helper/lib/not_a_root.dart': '// outside apps/modules/platform\n',
  };

  Future<ToolRun> files(
    TempWorkspace ws,
    List<String> args, {
    String from = '.',
  }) => probe.run(
    ['files', ...args],
    workingDirectory: from == '.' ? ws.root : '${ws.root}/$from',
    environment: const {
      // The user's own git settings must not decide what is ignored.
      'GIT_CONFIG_GLOBAL': '/dev/null',
      'GIT_CONFIG_NOSYSTEM': '1',
    },
  );

  List<String> listed(ToolRun run) => run.stdout
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty && !l.startsWith('⚠'))
      .toList();

  void git(TempWorkspace ws, List<String> args) {
    final result = Process.runSync(
      'git',
      [
        '-c',
        'user.name=test',
        '-c',
        'user.email=test@example.com',
        '-c',
        'commit.gpgsign=false',
        ...args,
      ],
      workingDirectory: ws.root,
      environment: const {
        'GIT_CONFIG_GLOBAL': '/dev/null',
        'GIT_CONFIG_NOSYSTEM': '1',
      },
    );
    expect(
      result.exitCode,
      0,
      reason: 'git ${args.join(' ')}: ${result.stderr}',
    );
  }

  /// A workspace committed to a fresh git repository.
  TempWorkspace repo([Map<String, String> more = const {}]) {
    final ws = TempWorkspace.create({...sources(), ...more});
    git(ws, ['init', '-q']);
    git(ws, ['add', '-A']);
    git(ws, ['commit', '-q', '-m', 'init']);
    return ws;
  }

  group('--all', () {
    test('from the workspace root reads every lib/ under apps, modules and platform', () async {
      final ws = TempWorkspace.create(sources());

      final run = await files(ws, ['--all']);

      expect(run, exitsWith(0));
      expect(
        listed(run)..sort(),
        [
          'apps/mobile/lib/main.dart',
          'modules/auth/feature/lib/ignored_by_git.dart',
          'modules/auth/feature/lib/pages/login_page.dart',
          'modules/auth/feature/lib/routing/deep/auth_route.dart',
          'platform/core/lib/core.dart',
        ],
      );
    });

    test(
      'never lists generated files, tests, gen/ output, caches or other roots',
      () async {
        final ws = TempWorkspace.create(sources());

        final out = listed(await files(ws, ['--all'])).join('\n');

        expect(out, isNot(contains('main.g.dart')));
        expect(out, isNot(contains('.freezed.dart')));
        expect(out, isNot(contains('firebase_options')));
        expect(out, isNot(contains('main_test.dart')));
        expect(out, isNot(contains('/gen/')));
        expect(out, isNot(contains('/test/')));
        expect(out, isNot(contains('.dart_tool')));
        expect(out, isNot(contains('/build/')));
        expect(out, isNot(contains('tools/helper')));
      },
    );

    test('from inside a package reads that package lib/ only', () async {
      final ws = TempWorkspace.create(sources());

      final run = await files(ws, ['--all'], from: 'modules/auth/feature');

      expect(
        listed(run)..sort(),
        [
          'lib/ignored_by_git.dart',
          'lib/pages/login_page.dart',
          'lib/routing/deep/auth_route.dart',
        ],
      );
    });

    test('a file git ignores is left out', () async {
      final ws = repo();

      final out = listed(await files(ws, ['--all']));

      expect(out, contains('modules/auth/feature/lib/pages/login_page.dart'));
      expect(
        out,
        isNot(contains('modules/auth/feature/lib/ignored_by_git.dart')),
      );
    }, skip: needsGit);

    test('outside a git repository nothing is treated as ignored', () async {
      final ws = TempWorkspace.create(sources());

      final out = listed(await files(ws, ['--all']));

      expect(out, contains('modules/auth/feature/lib/ignored_by_git.dart'));
    });
  });

  group('--exclude', () {
    test('drops the files a pattern matches', () async {
      final ws = TempWorkspace.create(sources());

      final out = listed(
        await files(ws, ['--all', '--exclude', '**/routing/**']),
      );

      expect(
        out,
        isNot(
          contains('modules/auth/feature/lib/routing/deep/auth_route.dart'),
        ),
      );
      expect(out, contains('modules/auth/feature/lib/pages/login_page.dart'));
    });

    test('`**/` spans several directories after a literal prefix', () async {
      // `**/` became `.[^/]*/` — one directory — so this pattern, two
      // directories below `modules/`, matched nothing.
      final ws = TempWorkspace.create(sources());

      final out = listed(
        await files(ws, ['--all', '--exclude', 'modules/**/routing/**']),
      );

      expect(
        out,
        isNot(
          contains('modules/auth/feature/lib/routing/deep/auth_route.dart'),
        ),
      );
      expect(out, contains('apps/mobile/lib/main.dart'));
    });

    test('a single `*` does not cross a directory', () async {
      final ws = TempWorkspace.create(sources());

      final out = listed(
        await files(ws, ['--all', '--exclude', 'lib/*_page.dart']),
      );

      // `pages/login_page.dart` is a directory deeper than `lib/`.
      expect(out, contains('modules/auth/feature/lib/pages/login_page.dart'));
    });

    test('several patterns all apply', () async {
      final ws = TempWorkspace.create(sources());

      final out = listed(
        await files(ws, [
          '--all',
          '--exclude',
          '**/routing/**',
          '--exclude',
          'platform/**',
        ]),
      );

      expect(out, isNot(contains('platform/core/lib/core.dart')));
      expect(
        out,
        isNot(
          contains('modules/auth/feature/lib/routing/deep/auth_route.dart'),
        ),
      );
      expect(out, contains('apps/mobile/lib/main.dart'));
    });

    test('generated files stay excluded when a pattern is given', () async {
      // The built-in exclusions once applied only when no --exclude was
      // given, so one pattern put every *.g.dart back in the review.
      final ws = TempWorkspace.create(sources());

      final out = listed(
        await files(ws, ['--all', '--exclude', 'nothing_matches_this']),
      );

      expect(out, isNot(contains('apps/mobile/lib/main.g.dart')));
      expect(out, isNot(contains('apps/mobile/lib/model.freezed.dart')));
    });
  });

  group('--file and --folder', () {
    test(
      'a named file is listed once even when --all reaches it too',
      () async {
        final ws = TempWorkspace.create(sources());

        final out = listed(
          await files(ws, ['--all', '--file', 'apps/mobile/lib/main.dart']),
        );

        expect(
          out.where((f) => f == 'apps/mobile/lib/main.dart'),
          hasLength(1),
        );
      },
    );

    test('a file that does not exist is reported and not listed', () async {
      final ws = TempWorkspace.create(sources());

      final run = await files(ws, ['--file', 'lib/ghost.dart']);

      expect(run.stdout, contains('File not found: lib/ghost.dart'));
      expect(listed(run), isEmpty);
    });

    test('a generated file named explicitly is still filtered out', () async {
      final ws = TempWorkspace.create(sources());

      final run = await files(ws, ['--file', 'apps/mobile/lib/main.g.dart']);

      expect(listed(run), isEmpty);
    });

    test('--folder lists the Dart files below it, filtered', () async {
      final ws = TempWorkspace.create(sources());

      final out = listed(
        await files(ws, ['--folder', 'modules/auth/feature/lib']),
      )..sort();

      expect(out, [
        'modules/auth/feature/lib/ignored_by_git.dart',
        'modules/auth/feature/lib/pages/login_page.dart',
        'modules/auth/feature/lib/routing/deep/auth_route.dart',
      ]);
    });

    test('a folder that does not exist lists nothing', () async {
      final ws = TempWorkspace.create(sources());

      expect(listed(await files(ws, ['--folder', 'nowhere'])), isEmpty);
    });
  });

  group('git', () {
    test('--changed lists modified tracked Dart files', () async {
      final ws = repo();
      ws.write({'apps/mobile/lib/main.dart': 'void main() { print(1); }\n'});

      final out = listed(await files(ws, ['--changed']));

      expect(out, ['apps/mobile/lib/main.dart']);
    }, skip: needsGit);

    test(
      '--changed leaves out a deleted file, which has nothing to review',
      () async {
        final ws = repo();
        File('${ws.root}/platform/core/lib/core.dart').deleteSync();
        ws.write({'apps/mobile/lib/main.dart': '// edited\n'});

        final out = listed(await files(ws, ['--changed']));

        expect(out, ['apps/mobile/lib/main.dart']);
      },
      skip: needsGit,
    );

    test('--changed with no change lists nothing', () async {
      final ws = repo();

      expect(listed(await files(ws, ['--changed'])), isEmpty);
    }, skip: needsGit);

    test(
      '--changed ignores changed files that are not Dart, generated or test',
      () async {
        final ws = repo();
        ws.write({
          'pubspec.yaml': 'name: ws2\nworkspace:\n',
          'apps/mobile/lib/main.g.dart': '// regenerated\n',
          'apps/mobile/test/main_test.dart': '// edited\n',
        });

        expect(listed(await files(ws, ['--changed'])), isEmpty);
      },
      skip: needsGit,
    );

    test('--staged lists what is staged, not what is only modified', () async {
      final ws = repo();
      ws.write({
        'apps/mobile/lib/main.dart': '// staged\n',
        'platform/core/lib/core.dart': '// only modified\n',
      });
      git(ws, ['add', 'apps/mobile/lib/main.dart']);

      final out = listed(await files(ws, ['--staged']));

      expect(out, ['apps/mobile/lib/main.dart']);
    }, skip: needsGit);

    test(
      '--staged lists a newly added file but not a staged deletion',
      () async {
        final ws = repo();
        ws.write({'apps/mobile/lib/added.dart': 'class Added {}\n'});
        git(ws, ['add', 'apps/mobile/lib/added.dart']);
        git(ws, ['rm', '-q', 'platform/core/lib/core.dart']);

        final out = listed(await files(ws, ['--staged']));

        expect(out, ['apps/mobile/lib/added.dart']);
      },
      skip: needsGit,
    );

    test('--changed outside a git repository lists nothing', () async {
      final ws = TempWorkspace.create(sources());

      expect(listed(await files(ws, ['--changed'])), isEmpty);
    });
  });

  group('validateFlutterProject', () {
    Future<String> validate(TempWorkspace ws) async => (await probe.run([
      'validate',
    ], workingDirectory: ws.root)).stdout.trim();

    test('a workspace root is a project', () async {
      expect(await validate(TempWorkspace.create(sources())), 'true');
    });

    test('a package with lib/ and a flutter dependency is a project', () async {
      final ws = TempWorkspace.create({
        'pubspec.yaml':
            'name: app\ndependencies:\n  flutter:\n    sdk: flutter\n',
        'lib/main.dart': '',
      });

      expect(await validate(ws), 'true');
    });

    test('a pure Dart package is not', () async {
      final ws = TempWorkspace.create({
        'pubspec.yaml': 'name: lib_only\ndependencies:\n  path: any\n',
        'lib/lib_only.dart': '',
      });

      expect(await validate(ws), 'false');
    });

    test('a pubspec without lib/ is not', () async {
      final ws = TempWorkspace.create({
        'pubspec.yaml':
            'name: app\ndependencies:\n  flutter:\n    sdk: flutter\n',
      });

      expect(await validate(ws), 'false');
    });

    test('a directory without a pubspec is not', () async {
      expect(await validate(TempWorkspace.create({'lib/a.dart': ''})), 'false');
    });
  });
}
