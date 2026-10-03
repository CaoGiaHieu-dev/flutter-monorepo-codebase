import 'package:test/test.dart';

import 'support/composer_fixture.dart';
import 'support/tool_harness.dart';

/// `tools/composer/composer.dart verify` — the checks that hold an app's
/// declaration to the source (Gate 0, stage 5).
///
/// | Check | Holds |
/// |:-:|:--|
/// | V3  | `capabilities:` equals the code, both directions; every required row has an implementer |
/// | V7  | every declared platform is one every composed package supports |
/// | V10 | what a composed package needs the app to register (`FirebaseOptions`) is registered, per flavor |
/// | V11 | the env files that exist hold exactly the keys `env:` declares |
/// | V12 | the entry point passes the profile; the DI smoke test exists and calls `checkAppContract` |
/// | V17 | no member pubspec but the root's has a top-level `workspace:` key (RULE-16) |
///
/// Each has a clean fixture and a violating one. The workspace is the `demo`
/// fixture of `support/composer_fixture.dart`, whose declaration is true of its
/// source until a test breaks one of them.
void main() {
  late CompiledTool tool;

  setUpAll(() async {
    tool = await CompiledTool.compile('tools/composer/composer.dart');
  });
  tearDownAll(() => tool.dispose());

  const manifestPath = 'apps/demo/app_manifest.yaml';
  const featureRegistrations = 'modules/foo/feature/lib/src/registrations.dart';
  const splashRegistration = 'modules/foo/feature/lib/src/splash.dart';

  Future<ToolRun> run(TempWorkspace ws, List<String> args) =>
      tool.run(args, workingDirectory: ws.root);

  /// `sync`, then `verify`: the declaration is the only thing under test.
  Future<ToolRun> syncAndVerify(TempWorkspace ws) async {
    final synced = await run(ws, ['sync']);
    expect(synced, exitsWith(0));
    return run(ws, ['verify']);
  }

  TempWorkspace demo({
    Map<String, String> extra = const {},
    Set<String> without = const {},
    String? manifest,
  }) {
    final files = demoWorkspaceFiles(manifest: manifest, extra: extra)
      ..removeWhere((path, _) => without.contains(path));
    return TempWorkspace.create(files);
  }

  /// Asserts [result] failed and names [parts] — file, key, problem, fix.
  void expectRefused(ToolRun result, List<Pattern> parts) {
    expect(result, exitsWith(1));
    for (final part in parts) {
      expect(result.output, contains(part));
    }
  }

  group('V17 the root is the only workspace node', () {
    test('a member without a `workspace:` key passes', () async {
      expect(await syncAndVerify(demo()), exitsWith(0));
    });

    test('a member that declares `workspace:` names its pubspec', () async {
      final ws = demo(
        extra: {
          'modules/foo/domain/pubspec.yaml':
              'name: domain_foo\n'
              'workspace:\n'
              '  - nested\n',
        },
      );
      expectRefused(await syncAndVerify(ws), [
        'modules/foo/domain/pubspec.yaml: workspace: a member pubspec '
            'declares its own `workspace:` list',
        'RULE-16',
      ]);
    });

    test('`sync` warns and still writes; `verify` is what fails', () async {
      final ws = demo(
        extra: {
          'apps/demo/pubspec.yaml':
              'name: demo_app\n'
              'workspace: [x]\n'
              'dependencies:\n'
              '  # composer:managed:deps — generated from app_manifest.yaml\n'
              '  # composer:end:deps\n',
        },
      );
      final synced = await run(ws, ['sync']);
      expect(synced, exitsWith(0));
      expect(synced.output, contains('apps/demo/pubspec.yaml: workspace:'));
      expectRefused(await run(ws, ['verify']), [
        'apps/demo/pubspec.yaml: workspace:',
      ]);
    });
  });

  group('V3 capabilities equal the code', () {
    test('a declaration that is true of the source passes', () async {
      expect(await syncAndVerify(demo()), exitsWith(0));
    });

    test(
      'provided, but nothing registers it, names file, key and fix',
      () async {
        // The feature registers the session bundle but no route module.
        final ws = demo(
          extra: {
            featureRegistrations: kFixtureFeatureRegistrations.replaceAll(
              RegExp(r'@LazySingleton\(as: IFeatureRouteModule\)[\s\S]*'),
              '',
            ),
          },
        );
        final result = await syncAndVerify(ws);

        expectRefused(result, [
          '$manifestPath: capabilities.routes: declared provided but no '
              'composed package or apps/demo/lib registers IFeatureRouteModule',
          'routes: { state: absent, reason: "the router has no stack routes" }',
        ]);
      },
    );

    test('says which package registers it when that one is not composed', () async {
      // The splash module exists in the workspace but the app does not
      // compose it: removing `feature_splash` while `splash: provided`.
      final ws = demo(
        manifest: demoManifest(
          capabilities: kCapabilities.replaceFirst(
            'splash: { state: absent, reason: "the native splash is kept through boot" }',
            'splash: provided',
          ),
        ),
        extra: {
          'modules/splash/feature/pubspec.yaml': 'name: feature_splash\n',
          'modules/splash/feature/lib/splash.dart': kFixtureSplashRegistration,
        },
      );
      final result = await syncAndVerify(ws);

      expectRefused(result, [
        '$manifestPath: capabilities.splash: declared provided but no composed '
            'package or apps/demo/lib registers IAppSplashScreen '
            '(feature_splash registers it but is not composed)',
        'splash: { state: absent, reason: "the native splash is kept" }',
      ]);
    });

    test(
      'absent, but something composed registers it, names the site',
      () async {
        final ws = demo(
          extra: {splashRegistration: kFixtureSplashRegistration},
        );
        final result = await syncAndVerify(ws);

        expectRefused(result, [
          '$manifestPath: capabilities.splash: declared absent but '
              'IAppSplashScreen is registered at $splashRegistration:3',
          'declare it provided (splash: provided)',
        ]);
      },
    );

    test('provided and registered by the app itself passes', () async {
      final ws = demo(
        manifest: demoManifest(
          capabilities: kCapabilities.replaceFirst(
            'splash: { state: absent, reason: "the native splash is kept through boot" }',
            'splash: provided',
          ),
        ),
        extra: {'apps/demo/lib/app/splash.dart': kFixtureSplashRegistration},
      );
      expect(await syncAndVerify(ws), exitsWith(0));
    });

    test('a bundle declared provided needs every member registered', () async {
      final ws = demo(
        extra: {
          featureRegistrations: kFixtureFeatureRegistrations.replaceFirst(
            '  @lazySingleton\n  ISessionGateway bindGateway'
                '(FooSession session) => session;\n',
            '',
          ),
        },
      );
      final result = await syncAndVerify(ws);

      expectRefused(result, [
        '$manifestPath: capabilities.session: declared provided but no '
            'composed package or apps/demo/lib registers ISessionGateway',
      ]);
    });

    test('implementing a contract is not registering it', () async {
      // GetIt resolves the exact type (RULE-14): `implements` registers
      // nothing, so the declaration is still wrong.
      final ws = demo(
        extra: {
          featureRegistrations: kFixtureFeatureRegistrations.replaceFirst(
            '@LazySingleton(as: IFeatureRouteModule)\n',
            '',
          ),
        },
      );

      expectRefused(await syncAndVerify(ws), [
        'capabilities.routes: declared provided',
      ]);
    });

    test('an example in a comment or a string is not a registration', () async {
      final ws = demo(
        extra: {
          splashRegistration:
              '/// @LazySingleton(as: IAppSplashScreen)\n'
              "const example = '@LazySingleton(as: IAppSplashScreen) class X {}';\n",
        },
      );
      // `splash` is declared absent and nothing registers it for real.
      expect(await syncAndVerify(ws), exitsWith(0));
    });

    test('a required contract nobody composed registers is refused', () async {
      final ws = demo(
        without: {'platform/foundation/common/lib/src/language_storage.dart'},
      );
      final result = await syncAndVerify(ws);

      expectRefused(result, [
        '$manifestPath: di_groups: required contract ILanguageStorage '
            '(`language_storage`) has no implementer among the composed '
            'packages',
      ]);
    });

    test('sync says so and still writes; verify is the gate', () async {
      final ws = demo(without: {featureRegistrations});
      final synced = await run(ws, ['sync']);

      expect(synced, exitsWith(0));
      expect(synced.output, contains('capabilities.routes: declared provided'));
      expect(synced.output, contains('`composer verify` fails until each'));
      expect(
        ws.read('apps/demo/lib/app/app_profile.dart'),
        contains('appFacts'),
      );
      expect(await run(ws, ['verify']), exitsWith(1));
    });
  });

  group('V7 every declared platform is one the composed packages support', () {
    /// `core_database` the way the repository declares it: no web (`drift`
    /// needs `dart:ffi`), composed in the `core` group.
    Map<String, String> database() => {
      'platform/infra/database/pubspec.yaml':
          'name: core_database\n'
          'platforms:\n'
          '  android:\n'
          '  ios:\n'
          '  macos:\n'
          '  windows:\n'
          '  linux:\n',
      'platform/infra/database/lib/di/module.dart': diModule(),
    };

    String manifest(String platforms) =>
        demoManifest(
          platforms: platforms,
          flavors: kFlavors,
        ).replaceFirst(
          'packages: [core_common]',
          'packages: [core_common, core_database]',
        );

    test('a platform every package supports passes', () async {
      final ws = demo(
        manifest: manifest('platforms:\n  android: { runner: committed }\n'),
        extra: database(),
      );
      expect(await syncAndVerify(ws), exitsWith(0));
    });

    test(
      'declaring web with core_database composed names the package',
      () async {
        final ws = demo(
          manifest: manifest(
            'platforms:\n'
            '  android: { runner: committed }\n'
            '  web: { runner: scaffold }\n',
          ),
          extra: database(),
        );
        final result = await run(ws, ['verify']);

        expectRefused(result, [
          '$manifestPath: platforms.web: core_database does not support web '
              '(its pubspec `platforms:` lists android, ios, windows, macos, '
              'linux) but the app composes it in di_groups `core`',
        ]);
        // Refused like V8: nothing is written.
        expect(ws.read('pubspec.yaml'), isNot(contains('apps/demo')));
      },
    );

    test('names the module that pulled a package in', () async {
      final ws = demo(
        manifest: demoManifest(
          platforms:
              'platforms:\n'
              '  android: { runner: committed }\n'
              '  web: { runner: scaffold }\n',
          flavors: kFlavors,
        ),
        extra: {
          'modules/foo/domain/pubspec.yaml':
              'name: domain_foo\nplatforms:\n  android:\n',
        },
      );

      expectRefused(await run(ws, ['verify']), [
        'platforms.web: domain_foo does not support web',
        'through module `foo` (domain)',
      ]);
    });

    test('a package reached only through another one is held to it too, '
        'and the message names the chain', () async {
      final ws = demo(
        manifest: demoManifest(
          platforms:
              'platforms:\n'
              '  android: { runner: committed }\n'
              '  web: { runner: scaffold }\n',
          flavors: kFlavors,
        ),
        extra: {
          ...database(),
          // `core_database` is not composed (no di_group names it): only
          // `domain_foo` links it, through `dependencies:`.
          'modules/foo/domain/pubspec.yaml':
              'name: domain_foo\ndependencies:\n  core_database: any\n',
        },
      );

      expectRefused(await run(ws, ['verify']), [
        'platforms.web: core_database does not support web',
        'the app links it through domain_foo -> core_database',
      ]);
    });

    test('a dev dependency is not linked into the app, so it is not '
        'followed', () async {
      final ws = demo(
        manifest: demoManifest(
          platforms: 'platforms:\n  web: { runner: scaffold }\n',
          flavors: 'flavors:\n  dev:\n  staging:\n  prod:\n',
        ),
        without: {'apps/demo/android/README.txt'},
        extra: {
          ...database(),
          'modules/foo/domain/pubspec.yaml':
              'name: domain_foo\ndev_dependencies:\n  core_database: any\n',
        },
      );
      expect(await syncAndVerify(ws), exitsWith(0));
    });

    test('a package that declares no platforms is not restricted', () async {
      final ws = demo(
        manifest: demoManifest(
          platforms: 'platforms:\n  web: { runner: scaffold }\n',
          flavors: 'flavors:\n  dev:\n  staging:\n  prod:\n',
        ),
        without: {'apps/demo/android/README.txt'},
      );
      expect(await syncAndVerify(ws), exitsWith(0));
    });
  });

  group('V10 what a composed package needs the app to register', () {
    const notifications =
        'name: core_notifications\n'
        'platforms:\n'
        '  android:\n'
        'composition:\n'
        '  app_provides:\n'
        '    FirebaseOptions:\n'
        '      per_flavor: true\n'
        '      hint: "apps/<id>/lib/firebase/firebase_module.dart"\n';

    Map<String, String> notificationsWorkspace(String? firebaseModule) => {
      'platform/infra/notifications/pubspec.yaml': notifications,
      'platform/infra/notifications/lib/di/module.dart': diModule(),
      'apps/demo/lib/firebase/firebase_module.dart': ?firebaseModule,
    };

    TempWorkspace app(String? firebaseModule) => demo(
      manifest: demoManifest(flavors: kFlavors).replaceFirst(
        '  - name: shell\n',
        '  - name: notifications\n'
            '    phase: after\n'
            '    packages: [core_notifications]\n'
            '    why: "FirebaseOptions come from the app, after core"\n'
            '  - name: shell\n',
      ),
      extra: notificationsWorkspace(firebaseModule),
    );

    test('FirebaseOptions registered for every flavor passes', () async {
      expect(await syncAndVerify(app(kFixtureFirebaseModule)), exitsWith(0));
    });

    test('a registration with no environment covers every flavor', () async {
      final ws = app(
        "import 'package:injectable/injectable.dart';\n"
        '@module\n'
        'abstract class FirebaseModule {\n'
        '  @lazySingleton\n'
        '  FirebaseOptions get options => throw UnimplementedError();\n'
        '}\n',
      );
      expect(await syncAndVerify(ws), exitsWith(0));
    });

    test('no prod FirebaseOptions fails, naming the flavor and the hint', () async {
      final ws = app(
        kFixtureFirebaseModule.replaceFirst(
          RegExp(
            r"  @lazySingleton\n  @Environment\('prod'\)\n  FirebaseOptions get prod[^\n]*\n",
          ),
          '',
        ),
      );
      final result = await syncAndVerify(ws);

      expectRefused(result, [
        '$manifestPath: composition.app_provides: core_notifications needs the '
            'app to register FirebaseOptions for flavor `prod`, but nothing '
            "under apps/demo/lib does — add an @Environment('prod') "
            'FirebaseOptions to a @module there',
        'apps/demo/lib/firebase/firebase_module.dart',
      ]);
      expect(result.output, isNot(contains('for flavor `dev`')));
    });

    test('no registration at all fails once per flavor', () async {
      final result = await syncAndVerify(app(null));

      expectRefused(result, [
        'for flavor `dev`',
        'for flavor `staging`',
        'for flavor `prod`',
      ]);
    });

    test(
      'a registration in a module package does not count: the app owns it',
      () async {
        final ws = app(null);
        ws.write({
          'modules/foo/feature/lib/src/firebase.dart': kFixtureFirebaseModule,
        });

        expectRefused(await syncAndVerify(ws), ['for flavor `prod`']);
      },
    );
  });

  group('V11 env files match env:', () {
    String manifest() => demoManifest(
      env:
          'env:\n'
          '  BASE_URL: { required_in: [prod] }\n'
          '  WEB_DOMAIN: { native_only: true }\n',
    );

    test('a file holding exactly the declared keys passes', () async {
      final ws = demo(
        manifest: manifest(),
        extra: {
          'apps/demo/env.dev':
              'BASE_URL=\n\n# native\nWEB_DOMAIN=example.com\n',
        },
      );
      expect(await syncAndVerify(ws), exitsWith(0));
    });

    test('a flavor with no env file is not compared', () async {
      expect(await syncAndVerify(demo(manifest: manifest())), exitsWith(0));
    });

    test(
      'a key the manifest does not declare fails, naming the file',
      () async {
        final ws = demo(
          manifest: manifest(),
          extra: {
            'apps/demo/env.dev': 'BASE_URL=\nWEB_DOMAIN=\nAPP_LINK_MODE=\n',
          },
        );

        expectRefused(await syncAndVerify(ws), [
          'apps/demo/env.dev: APP_LINK_MODE: not declared under `env:` in '
              '$manifestPath',
          '`APP_LINK_MODE: { native_only: true }`',
        ]);
      },
    );

    test('a declared key missing from the file fails', () async {
      final ws = demo(
        manifest: manifest(),
        extra: {'apps/demo/env.dev': 'BASE_URL=\n'},
      );

      expectRefused(await syncAndVerify(ws), [
        'apps/demo/env.dev: WEB_DOMAIN: declared under `env:` in $manifestPath '
            'but missing from this file',
        'add `WEB_DOMAIN=`',
      ]);
    });

    test('env.stg is the staging file', () async {
      final ws = demo(
        manifest: manifest(),
        extra: {'apps/demo/env.stg': 'BASE_URL=\nWEB_DOMAIN=\nOTHER=1\n'},
      );

      expectRefused(await syncAndVerify(ws), ['apps/demo/env.stg: OTHER:']);
    });
  });

  group('V12 the entry point and the smoke test', () {
    test(
      'an entry point passing the profile, and a smoke test, pass',
      () async {
        expect(await syncAndVerify(demo()), exitsWith(0));
      },
    );

    test('an entry point that drops profile: fails', () async {
      final ws = demo(
        extra: {
          'apps/demo/lib/main.dart': kFixtureMain.replaceFirst(
            '  profile: appProfile,\n',
            '',
          ),
        },
      );

      expectRefused(await syncAndVerify(ws), [
        '$manifestPath: app.entrypoint: apps/demo/lib/main.dart calls '
            'runShellApp without `profile:`',
        'Pass `profile: appProfile`',
      ]);
    });

    test(
      'a profile: named only in a comment, or in a nested call, is not it',
      () async {
        final ws = demo(
          extra: {
            'apps/demo/lib/main.dart':
                "import 'package:platform_app_shell/platform_app_shell.dart';\n"
                '// runShellApp(profile: appProfile)\n'
                'void main() => runShellApp(\n'
                '  hooks: ShellHooks(onError: wrap(profile: 1)),\n'
                '  configureDependencies: configureDependencies,\n'
                ');\n',
          },
        );

        expectRefused(await syncAndVerify(ws), [
          'calls runShellApp without `profile:`',
        ]);
      },
    );

    test('an entry point that never calls runShellApp fails', () async {
      final ws = demo(extra: {'apps/demo/lib/main.dart': 'void main() {}\n'});

      expectRefused(await syncAndVerify(ws), [
        'app.entrypoint: apps/demo/lib/main.dart never calls runShellApp(...)',
      ]);
    });

    test(
      'a missing entry point fails; app.entrypoint moves the check',
      () async {
        final missing = demo(without: {'apps/demo/lib/main.dart'});
        expectRefused(await syncAndVerify(missing), [
          'app.entrypoint: apps/demo/lib/main.dart does not exist',
        ]);

        final moved = demo(
          manifest: demoManifest(
            appBlock: 'app:\n  id: demo\n  name: Demo App\n  entrypoint: lib/boot.dart\n',
          ),
          extra: {'apps/demo/lib/boot.dart': kFixtureMain},
          without: {'apps/demo/lib/main.dart'},
        );
        expect(await syncAndVerify(moved), exitsWith(0));
      },
    );

    test('deleting the smoke test fails', () async {
      final ws = demo(without: {'apps/demo/test/di_smoke_test.dart'});

      expectRefused(await syncAndVerify(ws), [
        'apps/demo/test/di_smoke_test.dart: file: missing',
        'calls checkAppContract(...)',
      ]);
    });

    test('a smoke test that never calls checkAppContract fails', () async {
      final ws = demo(
        extra: {
          'apps/demo/test/di_smoke_test.dart':
              '// checkAppContract(appProfile)\nvoid main() {}\n',
        },
      );

      expectRefused(await syncAndVerify(ws), [
        'apps/demo/test/di_smoke_test.dart: checkAppContract: never called',
      ]);
    });
  });

  group('the real tree', () {
    /// The runtime matrix the shell's own check reports (`checkAppContract`):
    /// an optional contract no registration reaches is one the app declares
    /// absent. Held here from the static scan alone, on the committed apps.
    Map<String, ({bool absent, bool implemented})> rows(String report) {
      final out = <String, ({bool absent, bool implemented})>{};
      final section = report.split('### 4.').last.split('### 5.').first;
      for (final line in section.split('\n')) {
        final cells = line
            .split(RegExp(r'(?<!\\)\|'))
            .map((c) => c.trim())
            .toList();
        if (cells.length < 8 || !cells[3].contains('optional')) continue;
        out[cells[1].replaceAll('`', '')] = (
          absent: cells[4].startsWith('**absent**'),
          implemented: cells[5] != '—',
        );
      }
      return out;
    }

    Future<Set<String>> unregistered(String app) async {
      final result = await tool.run([
        'describe',
        '--app',
        app,
      ], workingDirectory: repoRoot);
      expect(result, exitsWith(0));
      final table = rows(result.stdout);
      expect(table, hasLength(14), reason: 'the 14 optional catalog rows');
      // Both directions, per row: provided <=> something registers it.
      for (final entry in table.entries) {
        expect(
          entry.value.absent,
          !entry.value.implemented,
          reason: '$app ${entry.key}',
        );
      }
      return {
        for (final e in table.entries)
          if (!e.value.implemented) e.key,
      };
    }

    test('mobile lacks IErrorReporter and IAnalytics, nothing else', () async {
      expect(await unregistered('mobile'), {'error_reporter', 'analytics'});
    });

    test('admin additionally lacks the splash, entry, dashboard and '
        'post-sign-in contracts', () async {
      expect(await unregistered('admin'), {
        'error_reporter',
        'analytics',
        'splash',
        'entry',
        'dashboard',
        'post_sign_in',
      });
    });
  });
}
