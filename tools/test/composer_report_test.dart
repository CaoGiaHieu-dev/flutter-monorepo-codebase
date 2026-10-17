import 'dart:convert';
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
///   out of step with `composer verify`;
/// - `describe --ci-matrix pr|full` prints one line of JSON and nothing else
///   (goldens `ci_matrix_pr.json` / `ci_matrix_full.json`, over a workspace
///   holding an admin-like and a mobile-like app — the repository's shape).
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

  /// `core_notifications` as the repository declares it: it links on every
  /// platform, Firebase Messaging delivers on four, and an app that composes
  /// it provides `FirebaseOptions`.
  const notificationsPubspec =
      'name: core_notifications\n'
      'composition:\n'
      '  push_platforms: [android, ios, macos, web]\n'
      '  app_provides:\n'
      '    FirebaseOptions:\n'
      '      per_flavor: true\n'
      '      hint: "apps/<id>/lib/firebase/firebase_module.dart"\n';

  /// The files of an app like `apps/mobile`: Android and iOS, push, a splash,
  /// two flavors that pin nothing yet; [platforms] replaces its platforms.
  Map<String, String> mobileLikeFiles({String? platforms}) =>
      demoWorkspaceFiles(
        manifest:
            demoManifest(
              env:
                  'env:\n'
                  '  BASE_URL: { required_in: [prod] }\n'
                  '  WEB_DOMAIN: { native_only: true }\n',
              platforms:
                  platforms ??
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
                  '    why: "FirebaseOptions come from the app, after core"\n'
                  '  - name: shell\n',
            ),
        extra: {
          'apps/demo/ios/README.txt': 'runner\n',
          'platform/infra/notifications/pubspec.yaml': notificationsPubspec,
          'platform/infra/notifications/lib/di/module.dart': diModule(),
          'modules/foo/feature/lib/src/splash.dart': kFixtureSplashRegistration,
          'apps/demo/lib/firebase/firebase_module.dart': kFixtureFirebaseModule,
        },
      );

  TempWorkspace mobileLike() => TempWorkspace.create(mobileLikeFiles());

  /// An app like `apps/admin`: web and a desktop platform, runners still to
  /// create, no push. Windows can pin, so the default `flavors:` block decides
  /// staging and prod.
  Map<String, String> adminLikeFiles({String? platforms}) => demoWorkspaceFiles(
    manifest: demoManifest(
      platforms:
          platforms ??
          'platforms:\n'
              '  windows: { runner: scaffold }\n'
              '  web: { runner: scaffold }\n',
      capabilities: kCapabilities,
    ),
  )..remove('apps/demo/android/README.txt');

  TempWorkspace adminLike() => TempWorkspace.create(adminLikeFiles());

  /// [files] (a `demo` workspace) with its app moved to `apps/<id>` and
  /// renamed `<id>` / `<id>_app`; the shared packages stay where they are.
  Map<String, String> asApp(Map<String, String> files, String id) => {
    for (final entry in files.entries)
      if (entry.key.startsWith('apps/demo/'))
        entry.key.replaceFirst('apps/demo/', 'apps/$id/'): entry.value
            .replaceAll('id: demo\n', 'id: $id\n')
            .replaceAll('demo_app', '${id}_app')
      else
        entry.key: entry.value,
  };

  /// The repository's shape: `admin` on the web and the three desktops,
  /// generated runners only, no push; `mobile` on committed Android and iOS
  /// runners with push, plus a generated web and Linux runner.
  TempWorkspace twoApps() => TempWorkspace.create({
    ...asApp(
      adminLikeFiles(
        platforms:
            'platforms:\n'
            '  windows: { runner: scaffold }\n'
            '  macos: { runner: scaffold }\n'
            '  linux: { runner: scaffold }\n'
            '  web: { runner: scaffold }\n',
      ),
      'admin',
    ),
    ...asApp(
      mobileLikeFiles(
        platforms:
            'platforms:\n'
            '  android: { runner: committed }\n'
            '  ios: { runner: committed }\n'
            '  web: { runner: scaffold }\n'
            '  linux: { runner: scaffold }\n',
      ),
      'mobile',
    ),
  });

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

    test('says what a TLS pin can do on each platform', () async {
      final report = (await run(adminLike(), [
        'describe',
        '--app',
        'demo',
      ])).stdout;

      // windows: a desktop platform sees the leaf certificate only.
      expect(
        report,
        contains(
          'can pin, the leaf certificate only (decision per flavor, §1)',
        ),
      );
      // web: the browser owns TLS.
      expect(report, contains('n/a (the browser owns TLS)'));
      expect(report, isNot(contains('has no implementation')));
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

      // core_notifications links everywhere: nothing blocks a platform.
      expect(report, contains('- **web** — no composed package blocks it'));
      expect(report, contains('- **windows** — no composed package blocks it'));

      // A package that declares `platforms:` does.
      ws.write({
        'platform/infra/notifications/pubspec.yaml':
            'name: core_notifications\nplatforms: [android, ios]\n',
      });
      final blocked = (await run(ws, ['describe', '--app', 'demo'])).stdout;
      expect(
        blocked,
        contains('- **windows** — core_notifications does not support it'),
      );
    });

    test(
      'an admin-like app: generated runners, deep links and push off',
      () async {
        final report = (await run(adminLike(), [
          'describe',
          '--app',
          'demo',
        ])).stdout;
        expect(
          report,
          contains(
            'Generate the runners (never committed): '
            '`dart tools/composer/composer.dart runners --app demo`',
          ),
        );
        expect(report, contains('| Deep links | Secure storage |'));
        expect(
          report,
          contains(
            'off (derived: a generated runner registers no URL scheme)',
          ),
        );
        expect(
          report,
          contains(
            'off (derived: the address bar is the deep link; the router reads '
            'it)',
          ),
        );
        expect(
          report,
          contains('- **all generated runners** — no native flavors'),
        );
        expect(report, isNot(contains('flutter create')));
      },
    );

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

  group('describe --ci-matrix', () {
    Future<String> matrix(String kind) async {
      final result = await run(twoApps(), ['describe', '--ci-matrix', kind]);
      expect(result, exitsWith(0), reason: result.output);
      // One line of JSON and nothing else, so `>> $GITHUB_OUTPUT` works.
      expect(result.stdout.trimRight().split('\n'), hasLength(1));
      expect(result.stdout, isNot(contains('Composer')));
      expect(jsonDecode(result.stdout), isA<List<Object?>>());
      return result.stdout;
    }

    test('pr: every app that declares web or linux', () async {
      final out = await matrix('pr');
      expectGolden('ci_matrix_pr.json', out);
      expect(
        out.trim(),
        '[{"app":"admin","web":true,"linux":true},'
        '{"app":"mobile","web":true,"linux":true}]',
      );
    });

    test(
      'full: android, ios, windows and macos legs, with how each boots',
      () async {
        final out = await matrix('full');
        expectGolden('ci_matrix_full.json', out);
        final rows = (jsonDecode(out) as List).cast<Map<String, Object?>>();
        expect(
          [for (final r in rows) '${r['app']}/${r['platform']}'],
          [
            'admin/windows',
            'admin/macos',
            'mobile/android',
            'mobile/ios',
          ],
        );
        // A committed Android / iOS runner has native flavors; a generated
        // one is told with APP_FLAVOR. Push on: the leg boots only with real
        // Firebase files.
        expect(rows[0]['flavor'], '--dart-define=APP_FLAVOR=dev');
        expect(rows[2]['flavor'], '--flavor dev');
        expect(rows[0]['boot'], 'test');
        expect(rows[2]['boot'], 'firebase');
        expect(rows[1]['os'], 'macos-latest');
        expect(rows[0]['os'], 'windows-latest');
        expect(rows[2]['os'], 'ubuntu-latest');
      },
    );

    test('an app on neither web nor linux is not in the pr matrix', () async {
      final result = await run(mobileLike(), ['describe', '--ci-matrix', 'pr']);
      expect(result, exitsWith(0));
      expect(result.stdout.trim(), '[]');
    });

    test(
      'a value other than pr or full, or with --catalog, is a usage error',
      () async {
        final ws = adminLike();
        expect(
          await run(ws, ['describe', '--ci-matrix', 'nightly']),
          exitsWith(64),
        );
        expect(await run(ws, ['describe', '--ci-matrix']), exitsWith(64));
        expect(
          await run(ws, ['describe', '--catalog', '--ci-matrix', 'pr']),
          exitsWith(64),
        );
        expect(await run(ws, ['verify', '--ci-matrix', 'pr']), exitsWith(64));
      },
    );
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
      expect(
        out,
        contains(
          'TLS pinning can apply on   android, ios, windows, macos, linux',
        ),
      );
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
