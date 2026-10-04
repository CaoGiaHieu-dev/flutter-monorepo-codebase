import 'dart:io';

import 'package:test/test.dart';

import 'support/fake_bin.dart';
import 'support/tool_harness.dart';

/// `tools/workspace_setup/configure.dart` — the setup step of a fresh clone,
/// as a process.
///
/// `firebase_stubs_test.dart` covers what `--stub-firebase` writes. This file
/// covers the script around it: the arguments, the help, the order of the
/// commands it runs, where it runs them, and that it stops at the first
/// failure with that command's exit code. `flutter` and `dart` are fakes on
/// `PATH` that only log how they were called, so nothing is cleaned,
/// resolved or generated.
void main() {
  late CompiledTool tool;
  setUpAll(() async {
    tool = await CompiledTool.compile('tools/workspace_setup/configure.dart');
  });
  tearDownAll(() => tool.dispose());

  /// The script finds the repository from its own location, so the snapshot
  /// is copied to `<workspace>/tools/workspace_setup/`.
  const script = 'tools/workspace_setup/configure.dill';

  TempWorkspace workspace([Map<String, String> more = const {}]) =>
      TempWorkspace.create({
        'pubspec.yaml': 'name: ws\nworkspace:\n  - apps/mobile\n',
        // A library with generated l10n.
        'platform/ui/core_ui/pubspec.yaml': 'name: core_ui\n',
        'platform/ui/core_ui/lib/core_ui.dart': '',
        'platform/ui/core_ui/l10n.yaml': 'arb-dir: lib/l10n\n',
        // A module package without l10n.
        'modules/auth/domain/pubspec.yaml': 'name: domain_auth\n',
        'modules/auth/domain/lib/domain_auth.dart': '',
        // A package with no lib/ at all gets no barrel.
        'tools/pubspec.yaml': 'name: core_tools\n',
        // An app: a composition root, never given a barrel.
        'apps/mobile/pubspec.yaml': 'name: mobile\n',
        'apps/mobile/app_manifest.yaml': 'app:\n  id: mobile\n',
        'apps/mobile/lib/main.dart': '',
        ...more,
      });

  const logOnly = 'exit 0';

  Future<ToolRun> run(
    TempWorkspace ws,
    FakeBin? bin, {
    List<String> args = const [],
    String? from,
  }) => tool.run(
    args,
    workingDirectory: from == null ? ws.root : '${ws.root}/$from',
    scriptPath: script,
    scriptRoot: ws.root,
    environment: bin?.environment,
  );

  group('arguments', () {
    test('--help prints the usage, exits 0 and runs nothing', () async {
      final ws = workspace();
      final bin = FakeBin.create({'flutter': logOnly, 'dart': logOnly});

      final run0 = await run(ws, bin, args: ['--help']);

      expect(run0, exitsWith(0));
      expect(
        run0.stdout,
        contains('Usage: dart tools/workspace_setup/configure.dart'),
      );
      expect(run0.stdout, contains('--stub-firebase'));
      expect(run0.stdout, contains('build_runner build --workspace'));
      expect(bin.calls, isEmpty);
    }, skip: skipWithoutPosixShell());

    test('-h is the same as --help', () async {
      final ws = workspace();
      final bin = FakeBin.create({'flutter': logOnly, 'dart': logOnly});

      final run0 = await run(ws, bin, args: ['-h']);

      expect(run0, exitsWith(0));
      expect(run0.stdout, contains('Usage:'));
      expect(bin.calls, isEmpty);
    }, skip: skipWithoutPosixShell());

    test('an unknown argument exits 64 before anything is run', () async {
      // The setup cleans the workspace, so a misspelt flag must not fall
      // through into it.
      final ws = workspace();
      final bin = FakeBin.create({'flutter': logOnly, 'dart': logOnly});

      final run0 = await run(ws, bin, args: ['--stub-firebas']);

      expect(run0, exitsWith(64));
      expect(run0.output, contains('Unknown argument(s): --stub-firebas'));
      expect(run0.stderr, contains('Usage:'));
      expect(bin.calls, isEmpty);
    }, skip: skipWithoutPosixShell());

    test('a known flag next to an unknown one still exits 64', () async {
      final ws = workspace();
      final bin = FakeBin.create({'flutter': logOnly, 'dart': logOnly});

      final run0 = await run(ws, bin, args: ['--stub-firebase', '--force']);

      expect(run0, exitsWith(64));
      expect(run0.output, contains('--force'));
      expect(bin.calls, isEmpty);
    }, skip: skipWithoutPosixShell());
  });

  group('the setup', () {
    test('runs the six steps in order and exits 0', () async {
      final ws = workspace();
      final bin = FakeBin.create({'flutter': logOnly, 'dart': logOnly});

      final run0 = await run(ws, bin);

      expect(run0, exitsWith(0));
      expect(run0.output, contains('Configuration completed successfully'));
      final calls = bin.calls.map((c) => c.split(' ')).toList();
      final steps = [for (final c in calls) '${c[0]} ${c.skip(2).join(' ')}'];
      expect(steps, [
        'flutter pub global activate flutterfire_cli',
        'flutter clean',
        'flutter pub get',
        'flutter gen-l10n',
        'dart run build_runner build --workspace',
        // One barrel pass per library package; the app and the package
        // without lib/ are left out. Sorted by path.
        'dart tools/barrel_generator/generate.dart ./modules/auth/domain/lib',
        'dart tools/barrel_generator/generate.dart ./platform/ui/core_ui/lib',
      ]);
    }, skip: skipWithoutPosixShell());

    test(
      'runs every command from the repository root, gen-l10n in its package',
      () async {
        final ws = workspace();
        final bin = FakeBin.create({'flutter': logOnly, 'dart': logOnly});

        await run(ws, bin);

        final dirs = {
          for (final c in bin.calls.map((c) => c.split(' ')))
            '${c[0]} ${c.skip(2).take(1).join()}': c[1],
        };
        expect(dirs['flutter clean'], ws.root);
        expect(dirs['dart run'], ws.root);
        expect(dirs['flutter gen-l10n'], '${ws.root}/platform/ui/core_ui');
      },
      skip: skipWithoutPosixShell(),
    );

    test(
      'finds the repository from the script, not the working directory',
      () async {
        final ws = workspace();
        final bin = FakeBin.create({'flutter': logOnly, 'dart': logOnly});

        final run0 = await run(ws, bin, from: 'apps/mobile/lib');

        expect(run0, exitsWith(0));
        expect(
          bin.calls.firstWhere(
            (c) => c.startsWith('flutter clean') || c.contains(' clean'),
          ),
          contains(ws.root),
        );
        expect(bin.calls.where((c) => c.contains('apps/mobile/lib ')), isEmpty);
      },
      skip: skipWithoutPosixShell(),
    );

    test('without any l10n.yaml it says so and skips gen-l10n', () async {
      final ws = workspace();
      File('${ws.root}/platform/ui/core_ui/l10n.yaml').deleteSync();
      final bin = FakeBin.create({'flutter': logOnly, 'dart': logOnly});

      final run0 = await run(ws, bin);

      expect(run0, exitsWith(0));
      expect(run0.output, contains('No l10n.yaml found.'));
      expect(bin.calls.where((c) => c.contains('gen-l10n')), isEmpty);
    }, skip: skipWithoutPosixShell());

    test(
      'generates localization in every package that has an l10n.yaml',
      () async {
        final ws = workspace({
          'modules/auth/feature/pubspec.yaml': 'name: feature_auth\n',
          'modules/auth/feature/l10n.yaml': 'arb-dir: lib/l10n\n',
        });
        final bin = FakeBin.create({'flutter': logOnly, 'dart': logOnly});

        final run0 = await run(ws, bin);

        expect(run0, exitsWith(0));
        final dirs = [
          for (final c in bin.calls)
            if (c.startsWith('flutter ${ws.root}') && c.endsWith(' gen-l10n'))
              c.split(' ')[1],
        ];
        expect(dirs, [
          '${ws.root}/modules/auth/feature',
          '${ws.root}/platform/ui/core_ui',
        ]);
      },
      skip: skipWithoutPosixShell(),
    );

    test('a failing command stops the run with its own exit code', () async {
      final ws = workspace();
      final bin = FakeBin.create({
        'flutter': '[ "\$1" = clean ] && exit 7\nexit 0',
        'dart': logOnly,
      });

      final run0 = await run(ws, bin);

      expect(run0, exitsWith(7));
      expect(
        run0.output,
        contains('Command "flutter clean" failed with exit code 7'),
      );
      expect(run0.output, isNot(contains('Configuration completed')));
      // Nothing after the failing step ran.
      expect(bin.calls.where((c) => c.contains(' pub get')), isEmpty);
      expect(bin.calls.where((c) => c.startsWith('dart ')), isEmpty);
    }, skip: skipWithoutPosixShell());

    test('a failing build_runner stops before the barrels', () async {
      final ws = workspace();
      final bin = FakeBin.create({
        'flutter': logOnly,
        'dart': '[ "\$1" = run ] && exit 1\nexit 0',
      });

      final run0 = await run(ws, bin);

      expect(run0, exitsWith(1));
      expect(
        run0.output,
        contains('build_runner build --workspace" failed with exit code 1'),
      );
      expect(bin.calls.where((c) => c.contains('barrel_generator')), isEmpty);
    }, skip: skipWithoutPosixShell());

    test('a failing barrel pass stops the run', () async {
      final ws = workspace();
      final bin = FakeBin.create({
        'flutter': logOnly,
        'dart': '[ "\$1" = tools/barrel_generator/generate.dart ] && exit 3\nexit 0',
      });

      final run0 = await run(ws, bin);

      expect(run0, exitsWith(3));
      expect(run0.output, contains('barrel_generator/generate.dart'));
    }, skip: skipWithoutPosixShell());
  });

  group('--stub-firebase', () {
    const module = '''
import 'firebase_options_dev.dart' as dev;
import 'firebase_options_prod.dart' as prod;
''';

    TempWorkspace withFirebase() => workspace({
      'apps/mobile/lib/firebase/firebase_module.dart': module,
    });

    test(
      'writes the stubs before the first command and lists them at the end',
      () async {
        final ws = withFirebase();
        final stub =
            '${ws.root}/apps/mobile/lib/firebase/firebase_options_dev.dart';
        // Records, at the first call, whether the stub already exists.
        final bin = FakeBin.create({
          'flutter': '[ -f "$stub" ] && echo present >> "$stub.seen"\nexit 0',
          'dart': logOnly,
        });

        final run0 = await run(ws, bin, args: ['--stub-firebase']);

        expect(run0, exitsWith(0));
        expect(
          ws.exists('apps/mobile/lib/firebase/firebase_options_dev.dart'),
          isTrue,
        );
        expect(
          ws.exists('apps/mobile/lib/firebase/firebase_options_prod.dart'),
          isTrue,
        );
        expect(
          ws.exists('apps/mobile/lib/firebase/firebase_options_dev.dart.seen'),
          isTrue,
        );
        expect(run0.output, contains('Firebase stubs (--stub-firebase):'));
        expect(
          run0.output,
          contains(
            '- stubbed apps/mobile/lib/firebase/firebase_options_dev.dart',
          ),
        );
        expect(run0.output, contains('are STUBS, not real configs'));
        expect(
          run0.output,
          contains('dart tools/firebase/firebase_config.dart --app <id>'),
        );
      },
      skip: skipWithoutPosixShell(),
    );

    test('without the flag nothing is stubbed', () async {
      final ws = withFirebase();
      final bin = FakeBin.create({'flutter': logOnly, 'dart': logOnly});

      final run0 = await run(ws, bin);

      expect(run0, exitsWith(0));
      expect(
        ws.exists('apps/mobile/lib/firebase/firebase_options_dev.dart'),
        isFalse,
      );
      expect(run0.output, isNot(contains('Firebase stubs')));
    }, skip: skipWithoutPosixShell());

    test('keeps a real options file and says so', () async {
      final ws = withFirebase();
      ws.write({
        'apps/mobile/lib/firebase/firebase_options_dev.dart': '// real\n',
      });
      final bin = FakeBin.create({'flutter': logOnly, 'dart': logOnly});

      final run0 = await run(ws, bin, args: ['--stub-firebase']);

      expect(run0, exitsWith(0));
      expect(
        ws.read('apps/mobile/lib/firebase/firebase_options_dev.dart'),
        '// real\n',
      );
      expect(
        run0.output,
        contains(
          '- kept existing apps/mobile/lib/firebase/firebase_options_dev.dart',
        ),
      );
    }, skip: skipWithoutPosixShell());

    test('nothing to stub is reported, not warned about', () async {
      final ws = workspace();
      final bin = FakeBin.create({'flutter': logOnly, 'dart': logOnly});

      final run0 = await run(ws, bin, args: ['--stub-firebase']);

      expect(run0, exitsWith(0));
      expect(run0.output, contains('Nothing to stub'));
      expect(run0.output, isNot(contains('are STUBS')));
    }, skip: skipWithoutPosixShell());
  });
}
