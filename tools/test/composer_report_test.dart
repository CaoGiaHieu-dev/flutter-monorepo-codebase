import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/composer_fixture.dart';
import 'support/tool_harness.dart';

/// `composer describe` and the app report: the page a newcomer reads first,
/// generated from the manifest and the composed packages.
///
/// - **goldens** for a mobile-like and an admin-like app: what `describe --app`
///   prints is the text of the README `report` region, and either changes only
///   when the manifest or a composed package does (regenerate with
///   `UPDATE_GOLDENS=1 dart test test/composer_report_test.dart`, then read the
///   diff);
/// - the region **round-trips**: `sync` writes it, `verify` agrees;
/// - the rendered report **passes `docs_check`** — it is Markdown, so a dead
///   backticked path would fail Gate 5;
/// - the facts text is a **fixed point of `dart format`** under the
///   repository's formatter options, so a local format pass cannot put an app
///   out of step with `composer verify`.
void main() {
  late CompiledTool composer;
  late CompiledTool docsCheck;

  setUpAll(() async {
    composer = await CompiledTool.compile('tools/composer/composer.dart');
    docsCheck = await CompiledTool.compile('tools/docs_check/check.dart');
  });
  tearDownAll(() async {
    await composer.dispose();
    await docsCheck.dispose();
  });

  const readmePath = 'apps/demo/README.md';
  const profilePath = 'apps/demo/lib/app/app_profile.dart';

  /// `core_notifications` as the repository declares it: not on the web with a
  /// service worker, and an app that composes it provides `FirebaseOptions`.
  const notificationsPubspec =
      'name: core_notifications\n'
      'platforms:\n'
      '  android:\n'
      '  ios:\n'
      '  macos:\n'
      '  web:\n'
      'composition:\n'
      '  app_provides:\n'
      '    FirebaseOptions:\n'
      '      per_flavor: true\n'
      '      hint: "apps/<id>/lib/firebase/firebase_module.dart"\n';

  /// An app like `apps/mobile`: Android and iOS, push, a splash, two flavors
  /// that pin nothing yet.
  TempWorkspace mobileLike() => TempWorkspace.create(
    demoWorkspaceFiles(
      manifest:
          demoManifest(
            env:
                'env:\n'
                '  BASE_URL: { required_in: [prod] }\n'
                '  WEB_DOMAIN: { native_only: true }\n',
            platforms:
                'platforms:\n'
                '  android: { runner: committed }\n'
                '  ios: { runner: committed }\n',
            capabilities: kCapabilities.replaceFirst(
              'splash: { state: absent, reason: "the native splash is kept through boot" }',
              'splash: provided',
            ),
            why: '    why: "mechanism only, before anything else"\n',
          ).replaceFirst(
            '  - name: shell\n',
            '  - name: notifications\n'
                '    phase: after\n'
                '    packages: [core_notifications]\n'
                '  - name: shell\n',
          ),
      extra: {
        'apps/demo/ios/README.txt': 'runner\n',
        'platform/infra/notifications/pubspec.yaml': notificationsPubspec,
        'platform/infra/notifications/lib/di/module.dart': diModule(),
        'modules/foo/feature/lib/src/splash.dart': kFixtureSplashRegistration,
        'apps/demo/lib/firebase/firebase_module.dart': kFixtureFirebaseModule,
      },
    ),
  );

  /// An app like `apps/admin`: web and desktop, runners still to create, no
  /// push, nothing that can pin.
  TempWorkspace adminLike() {
    final files = demoWorkspaceFiles(
      manifest: demoManifest(
        flavors: 'flavors:\n  dev:\n  staging:\n  prod:\n',
        platforms:
            'platforms:\n'
            '  windows: { runner: scaffold }\n'
            '  web: { runner: scaffold }\n',
        capabilities: kCapabilities,
      ),
    )..remove('apps/demo/android/README.txt');
    return TempWorkspace.create(files);
  }

  Future<ToolRun> run(TempWorkspace ws, List<String> args) =>
      composer.run(args, workingDirectory: ws.root);

  void expectGolden(String name, String actual) {
    final file = File(p.join(repoRoot, 'tools', 'test', 'golden', name));
    if (Platform.environment['UPDATE_GOLDENS'] == '1') {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(actual);
    }
    expect(
      file.existsSync(),
      isTrue,
      reason: 'no golden ${file.path}: run with UPDATE_GOLDENS=1',
    );
    expect(
      actual,
      file.readAsStringSync(),
      reason:
          'the report changed; if intended, regenerate with UPDATE_GOLDENS=1',
    );
  }

  group('describe --app', () {
    test('a mobile-like app', () async {
      final ws = mobileLike();
      final result = await run(ws, ['describe', '--app', 'demo']);
      expect(result, exitsWith(0));
      expectGolden('describe_mobile_like.txt', result.stdout);
    });

    test('an admin-like app', () async {
      final ws = adminLike();
      final result = await run(ws, ['describe', '--app', 'demo']);
      expect(result, exitsWith(0));
      expectGolden('describe_admin_like.txt', result.stdout);
    });

    test('is the text of the README report region', () async {
      final ws = mobileLike();
      expect(await run(ws, ['sync']), exitsWith(0));
      final describe = await run(ws, ['describe', '--app', 'demo']);

      expect(ws.read(readmePath), contains(describe.stdout.trimRight()));
    });

    test('an unknown app is refused', () async {
      final result = await run(mobileLike(), ['describe', '--app', 'nope']);
      expect(result, exitsWith(1));
      expect(
        result.output,
        contains('No app matches `--app nope`. Known: demo.'),
      );
    });

    test('says what blocks a platform the app does not declare', () async {
      final ws = mobileLike();
      final report = (await run(ws, ['describe', '--app', 'demo'])).stdout;

      expect(report, contains('- **web** — no composed package blocks it'));
      expect(report, contains('- **macos** — no composed package blocks it'));
      expect(
        report,
        contains('- **windows** — core_notifications does not support it'),
      );
    });

    test('lists what the app must provide, from the composed packages', () async {
      final report = (await run(mobileLike(), [
        'describe',
        '--app',
        'demo',
      ])).stdout;
      expect(
        report,
        contains(
          '- `FirebaseOptions` for `core_notifications`: one registration per '
          'flavor (dev, staging, prod). apps/demo/lib/firebase/firebase_module.dart.',
        ),
      );
      final admin = (await run(adminLike(), [
        'describe',
        '--app',
        'demo',
      ])).stdout;
      expect(
        admin,
        contains('**This app must provide:** nothing beyond its composition.'),
      );
    });

    test('names what to revisit before shipping', () async {
      final report = (await run(mobileLike(), [
        'describe',
        '--app',
        'demo',
      ])).stdout;
      expect(
        report,
        contains(
          '- `flavors.prod.ssl_pinning`: **disabled** — no SPKI pins provisioned yet',
        ),
      );
    });
  });

  group('describe --catalog', () {
    test('prints every key, the catalog and the derived defaults', () async {
      final result = await run(mobileLike(), ['describe', '--catalog']);
      expect(result, exitsWith(0));
      final out = result.stdout;

      expect(out, contains('MANIFEST KEYS'));
      for (final key in [
        'app.id',
        'app.name',
        'app.entrypoint',
        'flavors.<f>',
        'flavors.<f>.ssl_pinning',
        'env.<KEY>',
        'platforms.<p>',
        'platforms.<p>.runner',
        'platforms.<p>.splash',
        'capabilities.<id>',
        'di_groups[].why',
      ]) {
        expect(out, contains('  $key\n'), reason: key);
      }
      expect(out, contains('SHELL CONTRACTS'));
      expect(out, contains('session_state'));
      expect(out, contains('ISessionState'));
      expect(out, contains('DERIVED DEFAULTS'));
      expect(out, contains('TLS pinning can apply on   android, ios'));
    });

    test('works on a workspace whose manifests are broken', () async {
      final ws = TempWorkspace.create(
        demoWorkspaceFiles(
          manifest: demoManifest(appBlock: 'app:\n  id: demo\n'),
        ),
      );
      expect(await run(ws, ['describe', '--catalog']), exitsWith(0));
    });

    test('--catalog belongs to describe', () async {
      expect(await run(adminLike(), ['sync', '--catalog']), exitsWith(64));
    });
  });

  group('the README report region', () {
    test('sync writes it and verify agrees', () async {
      final ws = mobileLike();
      expect(await run(ws, ['sync']), exitsWith(0));

      final readme = ws.read(readmePath);
      expect(readme, contains('### 2. Platforms (c)'));
      expect(
        readme,
        contains('### 4. What the shell resolves from this app (d)'),
      );
      expect(await run(ws, ['verify']), exitsWith(0));
    });

    test('the rendered report passes docs_check', () async {
      final ws = mobileLike();
      expect(await run(ws, ['sync']), exitsWith(0));

      final docs = TempWorkspace.create({
        'pubspec.yaml': 'name: docs_ws\n',
        // The one repo path the report backticks.
        'apps/demo/app_manifest.yaml': ws.read('apps/demo/app_manifest.yaml'),
        readmePath: ws.read(readmePath),
      });
      final result = await docsCheck.run(
        const [],
        workingDirectory: docs.root,
        scriptPath: 'tools/docs_check/check.dill',
      );

      expect(result, exitsWith(0));
      expect(
        result.output,
        contains('OK — every documented path exists on disk.'),
      );
    });

    test('an admin-like report passes docs_check too — a scaffold runner is '
        'never a backticked path', () async {
      final ws = adminLike();
      expect(await run(ws, ['sync']), exitsWith(0));

      final docs = TempWorkspace.create({
        'pubspec.yaml': 'name: docs_ws\n',
        'apps/demo/app_manifest.yaml': ws.read('apps/demo/app_manifest.yaml'),
        readmePath: ws.read(readmePath),
      });
      final result = await docsCheck.run(
        const [],
        workingDirectory: docs.root,
        scriptPath: 'tools/docs_check/check.dill',
      );

      expect(result, exitsWith(0));
    });
  });

  group('the facts region', () {
    for (final name in ['mobile-like', 'admin-like']) {
      test('$name text is a fixed point of dart format', () async {
        final ws = name == 'mobile-like' ? mobileLike() : adminLike();
        expect(await run(ws, ['sync']), exitsWith(0));
        // The repository's formatter options, which `dart format` reads from
        // the nearest analysis_options.yaml.
        ws.write({
          'analysis_options.yaml':
              'formatter:\n  page_width: 80\n  trailing_commas: preserve\n',
        });

        final format = await Process.run(dartExecutable, [
          'format',
          '--output=none',
          '--set-exit-if-changed',
          p.join(ws.root, profilePath),
        ]);

        expect(
          format.exitCode,
          0,
          reason:
              'dart format would change the generated facts:\n'
              '${format.stdout}\n${format.stderr}',
        );
      });
    }
  });
}
