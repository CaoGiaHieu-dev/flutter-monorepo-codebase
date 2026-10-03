import 'dart:convert';

import 'package:test/test.dart';

import 'support/composer_fixture.dart';
import 'support/tool_harness.dart';

/// `tools/composer/composer.dart` — manifest v2: what an app declares about
/// itself, and the checks `composer verify` (CI Gate 0) holds it to.
///
/// One clean and one violating fixture per check:
///
/// | Check | Holds |
/// |:-:|:--|
/// | V1  | closed vocabularies, types; `app.kind` and unknown keys refused |
/// | V2  | every optional catalog id has a state; no unknown id |
/// | V4  | the members of a bundle share one state |
/// | V5  | `splash: dart` needs capability `splash` provided |
/// | V6  | `committed` => the runner folder exists; `scaffold` => it does not |
/// | V9  | a pin decision per flavor where a declared platform can pin |
/// | V13 | the `facts`, `report` and `modules` regions equal regeneration |
/// | V14 | no reason is empty, `TODO` or `TBD` |
///
/// Every refusal names the file and the key (`<file>: <key>: <problem>`), is
/// reported together with the others, and writes nothing.
void main() {
  late CompiledTool tool;

  setUpAll(() async {
    tool = await CompiledTool.compile('tools/composer/composer.dart');
  });
  tearDownAll(() => tool.dispose());

  const manifestPath = 'apps/demo/app_manifest.yaml';
  const profilePath = 'apps/demo/lib/app/app_profile.dart';
  const injectionPath = 'apps/demo/lib/di/injection.dart';
  const readmePath = 'apps/demo/README.md';

  TempWorkspace workspace({
    String? manifest,
    Map<String, String> extra = const {},
    Set<String> without = const {},
  }) {
    final files = demoWorkspaceFiles(manifest: manifest, extra: extra)
      ..removeWhere((path, _) => without.contains(path));
    return TempWorkspace.create(files);
  }

  Future<ToolRun> run(TempWorkspace ws, List<String> args) =>
      tool.run(args, workingDirectory: ws.root);

  /// A refusal: exit 1, the message, and nothing written.
  Future<void> expectRefused(
    TempWorkspace ws,
    Matcher message, {
    List<String> command = const ['verify'],
  }) async {
    final result = await run(ws, command);
    expect(result, exitsWith(1));
    expect(result.output, message);
    expect(
      ws.read('pubspec.yaml'),
      isNot(contains('apps/demo')),
      reason: 'a refused manifest must not write anything',
    );
  }

  /// [capabilities] with [line] swapped for [replacement].
  String capabilitiesWith(String line, String replacement) =>
      kCapabilities.replaceFirst(line, replacement);

  group('a clean declaration', () {
    test('sync writes the facts, the report and the entry point, then verify '
        'passes', () async {
      final ws = workspace();

      expect(await run(ws, ['sync']), exitsWith(0));

      final facts = ws.read(profilePath);
      expect(facts, contains("id: 'demo',"));
      expect(facts, contains("name: 'Demo App',"));
      expect(
        facts,
        contains('flavors: {Flavor.dev, Flavor.staging, Flavor.prod},'),
      );
      expect(facts, contains('AppPlatform.android: PlatformFacts('));
      expect(facts, contains('runner: RunnerKind.committed,'));
      // Every PlatformFacts field is explicit, each with where it came from.
      expect(facts, contains('// derived: capability `splash` is absent'));
      expect(facts, contains('splash: SplashMode.native,'));
      expect(
        facts,
        contains('// derived: core_notifications is not composed'),
      );
      expect(facts, contains('push: false,'));
      expect(facts, contains('deepLinks: true,'));
      expect(facts, contains('orientation: OrientationPolicy.phonesPortrait,'));
      // A bundle expands to its members, each marked as such.
      expect(
        facts,
        contains("'session_state': CapabilityExpectation.provided(),"),
      );
      expect(
        facts,
        contains("'session_gateway': CapabilityExpectation.provided(),"),
      );
      expect(facts, contains("'splash': CapabilityExpectation.absent("));
      expect(
        facts,
        contains('// default\n    Flavor.dev: SslPinning.disabled('),
      );
      // The hand-written part is untouched.
      expect(
        facts,
        contains('const AppProfile appProfile = AppProfile(facts: appFacts);'),
      );

      final injection = ws.read(injectionPath);
      expect(injection, contains('Future<void> configureDependencies('));
      expect(
        injection,
        contains('getIt.enableRegisteringMultipleInstancesOfOneType();'),
      );
      expect(injection, contains('@InjectableInit('));
      expect(injection, contains('Future<void> resetDependencies()'));

      final readme = ws.read(readmePath);
      expect(readme, contains('## demo — Demo App'));
      expect(readme, contains('### 1. Identity (b)'));

      final verify = await run(ws, ['verify']);
      expect(verify, exitsWith(0));
      expect(verify.output, contains('Generated artifacts are up to date.'));
    });

    test(
      'a pinned flavor is emitted as SslPinning.pinned(leaf, backup)',
      () async {
        final leaf = base64.encode(List<int>.generate(32, (i) => i));
        final backup = base64.encode(List<int>.generate(32, (i) => i + 1));
        final ws = workspace(
          manifest: demoManifest(
            flavors:
                'flavors:\n'
                '  dev:\n'
                '  staging:\n'
                '    ssl_pinning: { disabled: "no pins yet" }\n'
                '  prod:\n'
                '    ssl_pinning: { pins: ["$leaf", "$backup"] }\n',
          ),
        );

        expect(await run(ws, ['sync']), exitsWith(0));

        final facts = ws.read(profilePath);
        expect(facts, contains('Flavor.prod: SslPinning.pinned('));
        expect(facts, contains("'$leaf',\n"));
        expect(facts, contains("'$backup',\n"));
        expect(await run(ws, ['verify']), exitsWith(0));
      },
    );

    test(
      'environment keys: Dart ones are emitted, native-only ones are not',
      () async {
        final ws = workspace(
          manifest: demoManifest(
            env:
                'env:\n'
                '  BASE_URL: { required_in: [prod] }\n'
                '  WEB_DOMAIN: { native_only: true }\n',
          ),
        );

        expect(await run(ws, ['sync']), exitsWith(0));

        final facts = ws.read(profilePath);
        expect(facts, contains("key: 'BASE_URL',"));
        expect(facts, contains("value: String.fromEnvironment('BASE_URL'),"));
        expect(facts, contains('requiredIn: {Flavor.prod},'));
        expect(facts, isNot(contains('WEB_DOMAIN')));
        expect(ws.read(readmePath), contains('native only (Gradle / Xcode)'));
      },
    );

    test('a group `why` reaches the report', () async {
      final ws = workspace(
        manifest: demoManifest(
          why: '    why: "mechanism only, before anything else"\n',
        ),
      );

      expect(await run(ws, ['sync']), exitsWith(0));
      expect(
        ws.read(readmePath),
        contains('mechanism only, before anything else'),
      );
    });
  });

  group('V1 — vocabulary, shape and the removed key', () {
    test('app.kind is refused with the removal message', () async {
      final ws = workspace(
        manifest: demoManifest(
          appBlock: 'app:\n  id: demo\n  name: Demo App\n  kind: flutter\n',
        ),
      );
      await expectRefused(
        ws,
        contains(
          '$manifestPath: app.kind: removed — it had no consumer; delete the '
          'line',
        ),
      );
    });

    test('app.name is required', () async {
      final ws = workspace(
        manifest: demoManifest(appBlock: 'app:\n  id: demo\n'),
      );
      await expectRefused(
        ws,
        contains(
          '$manifestPath: app.name: expected a non-empty string, got nothing',
        ),
      );
    });

    test('a flavor outside dev / staging / prod', () async {
      final ws = workspace(
        manifest: demoManifest(flavors: 'flavors:\n  dev:\n  beta:\n'),
      );
      await expectRefused(
        ws,
        contains(
          '$manifestPath: flavors.beta: expected one of dev, staging, prod, '
          'got a string (`beta`)',
        ),
      );
    });

    test('a platform outside the six', () async {
      final ws = workspace(
        manifest: demoManifest(
          platforms: 'platforms:\n  symbian: { runner: committed }\n',
        ),
      );
      await expectRefused(
        ws,
        contains(
          '$manifestPath: platforms.symbian: expected one of android, ios, '
          'web, windows, macos, linux',
        ),
      );
    });

    test('a runner that is neither committed nor scaffold', () async {
      final ws = workspace(
        manifest: demoManifest(
          platforms: 'platforms:\n  android: { runner: bundled }\n',
        ),
      );
      await expectRefused(
        ws,
        contains(
          '$manifestPath: platforms.android.runner: expected one of '
          'committed, scaffold, got a string (`bundled`)',
        ),
      );
    });

    test('a key nothing reads is unknown, not ignored', () async {
      final ws = workspace(
        manifest: demoManifest(
          platforms:
              'platforms:\n  android: { runner: committed, sound: true }\n',
        ),
      );
      await expectRefused(
        ws,
        contains(
          '$manifestPath: platforms.android.sound: unknown key — expected '
          'runner, splash, push, deep_links, orientation, window',
        ),
      );
    });

    test('a missing platforms section prints the YAML to paste', () async {
      final ws = workspace(manifest: demoManifest(platforms: ''));
      final result = await run(ws, ['verify']);
      expect(result, exitsWith(1));
      expect(
        result.output,
        allOf(
          contains(
            '$manifestPath: platforms: expected a map naming at least '
            'one platform',
          ),
          contains('android: { runner: committed }'),
        ),
      );
    });

    test('a missing capabilities section is refused', () async {
      final ws = workspace(manifest: demoManifest(capabilities: ''));
      await expectRefused(
        ws,
        contains('$manifestPath: capabilities: expected a map of contract id'),
      );
    });

    test('every problem is reported at once', () async {
      final ws = workspace(
        manifest: demoManifest(
          appBlock: 'app:\n  id: demo\n  kind: flutter\n',
          flavors: 'flavors:\n  beta:\n',
          platforms: 'platforms:\n  symbian: { runner: committed }\n',
        ),
      );
      final result = await run(ws, ['verify']);
      expect(result, exitsWith(1));
      expect(
        result.output,
        allOf(
          contains('app.kind: removed'),
          contains('app.name: expected'),
          contains('flavors.beta: expected'),
          contains('platforms.symbian: expected'),
          contains('Refusing to compose: 4 problem(s)'),
        ),
      );
    });
  });

  group('V2 — every optional contract has a declared state', () {
    test('a missing id is refused with the line to paste', () async {
      final ws = workspace(
        manifest: demoManifest(
          capabilities:
              'capabilities:\n'
              '  session: provided\n',
        ),
      );
      final result = await run(ws, ['verify']);
      expect(result, exitsWith(1));
      expect(
        result.output,
        allOf(
          contains(
            '$manifestPath: capabilities: no state declared for splash, routes',
          ),
          contains(
            'splash: { state: absent, reason: "the native splash is kept" }',
          ),
          contains(
            'routes: { state: absent, reason: "the router has no stack routes" }',
          ),
          contains('`splash: provided`'),
        ),
      );
    });

    test('a half-declared bundle names the members that are missing', () async {
      final ws = workspace(
        manifest: demoManifest(
          capabilities: capabilitiesWith(
            'session: provided\n',
            'session_state: provided\n',
          ),
        ),
      );
      await expectRefused(
        ws,
        contains('capabilities: no state declared for session_gateway'),
      );
    });

    test('an unknown id is refused, and the known ones are listed', () async {
      final ws = workspace(
        manifest: demoManifest(
          capabilities: '$kCapabilities  bluetooth: provided\n',
        ),
      );
      await expectRefused(
        ws,
        contains(
          '$manifestPath: capabilities.bluetooth: unknown contract id — '
          '`composer describe --catalog` lists them (session, splash, routes)',
        ),
      );
    });

    test(
      'a contract declared by its bundle and by itself is declared twice',
      () async {
        final ws = workspace(
          manifest: demoManifest(
            capabilities: '$kCapabilities  session_state: provided\n',
          ),
        );
        await expectRefused(
          ws,
          contains(
            '`session_state` is declared twice (session_state and session)',
          ),
        );
      },
    );

    test('a required row needs no declaration', () async {
      // `language_storage` is a required row of the fixture catalog and is
      // absent from kCapabilities: the clean fixture already passes.
      expect(await run(workspace(), ['sync']), exitsWith(0));
    });
  });

  group('V4 — the members of a bundle share one state', () {
    test('one provided, one absent is refused', () async {
      final ws = workspace(
        manifest: demoManifest(
          capabilities: capabilitiesWith(
            'session: provided\n',
            'session_state: provided\n'
                '  session_gateway: { state: absent, reason: "no gateway" }\n',
          ),
        ),
      );
      await expectRefused(
        ws,
        contains(
          'the members of bundle `session` share one state, but '
          'session_state is provided and session_gateway is absent — declare '
          'the bundle once: `session: provided`',
        ),
      );
    });

    test('members declared one by one in the same state are fine', () async {
      final ws = workspace(
        manifest: demoManifest(
          capabilities: capabilitiesWith(
            'session: provided\n',
            'session_state: provided\n  session_gateway: provided\n',
          ),
        ),
      );
      expect(await run(ws, ['sync']), exitsWith(0));
      expect(await run(ws, ['verify']), exitsWith(0));
    });
  });

  group('V5 — a Dart splash needs the splash capability', () {
    const dartSplash =
        'platforms:\n  android: { runner: committed, splash: dart }\n';

    test('splash: dart with the capability absent is refused', () async {
      final ws = workspace(manifest: demoManifest(platforms: dartSplash));
      await expectRefused(
        ws,
        contains(
          '$manifestPath: platforms.android.splash: a Dart splash needs '
          'capability `splash` provided, which `capabilities` declares absent',
        ),
      );
    });

    test('with the capability provided it is accepted and emitted', () async {
      final ws = workspace(
        manifest: demoManifest(
          platforms: dartSplash,
          capabilities: capabilitiesWith(
            'splash: { state: absent, reason: "the native splash is kept through boot" }',
            'splash: provided',
          ),
        ),
      );
      expect(await run(ws, ['sync']), exitsWith(0));
      expect(
        ws.read(profilePath),
        contains('// manifest\n      splash: SplashMode.dart,'),
      );
    });

    test('left to the default, the capability decides: provided means Dart, '
        'iOS stays native', () async {
      final ws = workspace(
        manifest: demoManifest(
          platforms:
              'platforms:\n'
              '  android: { runner: committed }\n'
              '  ios: { runner: committed }\n',
          capabilities: capabilitiesWith(
            'splash: { state: absent, reason: "the native splash is kept through boot" }',
            'splash: provided',
          ),
        ),
        extra: {'apps/demo/ios/README.txt': 'runner\n'},
      );
      expect(await run(ws, ['sync']), exitsWith(0));
      final facts = ws.read(profilePath);
      expect(facts, contains('// derived: capability `splash` is provided'));
      expect(facts, contains('splash: SplashMode.dart,'));
      expect(
        facts,
        contains('// default: iOS keeps its native splash for the whole boot'),
      );
    });
  });

  group('V6 — the runner folder agrees with the declaration', () {
    test('committed with no folder is refused', () async {
      final ws = workspace(without: {'apps/demo/android/README.txt'});
      await expectRefused(
        ws,
        contains(
          '$manifestPath: platforms.android.runner: declared `committed`, '
          'but apps/demo/android/ does not exist',
        ),
      );
    });

    test('scaffold with a folder is refused', () async {
      final ws = workspace(
        manifest: demoManifest(
          platforms: 'platforms:\n  android: { runner: scaffold }\n',
        ),
      );
      await expectRefused(
        ws,
        contains(
          '$manifestPath: platforms.android.runner: declared `scaffold`, but '
          'apps/demo/android/ exists',
        ),
      );
    });

    test('scaffold with no folder is accepted and the report prints the '
        'flutter create line', () async {
      final ws = workspace(
        manifest: demoManifest(
          platforms: 'platforms:\n  web: { runner: scaffold }\n',
          flavors: 'flavors:\n  dev:\n  prod:\n',
        ),
        without: {'apps/demo/android/README.txt'},
      );
      expect(await run(ws, ['sync']), exitsWith(0));
      expect(
        ws.read(readmePath),
        contains(
          'flutter create --platforms=web --org com.example --project-name '
          'demo_app .',
        ),
      );
      expect(await run(ws, ['verify']), exitsWith(0));
    });
  });

  group('V9 — a pinning decision per flavor where a platform can pin', () {
    test('a missing decision is refused with the paste-ready line', () async {
      final ws = workspace(
        manifest: demoManifest(
          flavors:
              'flavors:\n'
              '  dev:\n'
              '  staging:\n'
              '    ssl_pinning: { disabled: "no pins yet" }\n'
              '  prod:\n',
        ),
      );
      await expectRefused(
        ws,
        contains(
          '$manifestPath: flavors.prod.ssl_pinning: decide — pins: '
          '["<leaf>", "<backup>"] or disabled: "<reason>" (android can pin)',
        ),
      );
    });

    test(
      'dev needs none: it defaults to a stated, disabled decision',
      () async {
        expect(await run(workspace(), ['sync']), exitsWith(0));
      },
    );

    test(
      'a key where no declared platform can pin is refused as dead',
      () async {
        final ws = workspace(
          manifest: demoManifest(
            flavors:
                'flavors:\n'
                '  dev:\n'
                '  prod:\n'
                '    ssl_pinning: { disabled: "no pins yet" }\n',
            platforms: 'platforms:\n  web: { runner: scaffold }\n',
          ),
          without: {'apps/demo/android/README.txt'},
        );
        await expectRefused(
          ws,
          contains(
            '$manifestPath: flavors.prod.ssl_pinning: no declared platform can '
            'pin TLS (web: the browser owns TLS on web',
          ),
        );
      },
    );

    test('and no decision is needed there at all', () async {
      final ws = workspace(
        manifest: demoManifest(
          flavors: 'flavors:\n  dev:\n  staging:\n  prod:\n',
          platforms: 'platforms:\n  web: { runner: scaffold }\n',
        ),
        without: {'apps/demo/android/README.txt'},
      );
      expect(await run(ws, ['sync']), exitsWith(0));
      final facts = ws.read(profilePath);
      expect(facts, contains('sslPinning: SslPinningPolicy.none(),'));
      expect(
        ws.read(readmePath),
        contains('n/a — no declared platform can pin TLS'),
      );
    });

    test('a pin list needs two hashes', () async {
      final one = base64.encode(List<int>.filled(32, 7));
      final ws = workspace(
        manifest: demoManifest(
          flavors:
              'flavors:\n'
              '  dev:\n'
              '  staging:\n'
              '    ssl_pinning: { disabled: "no pins yet" }\n'
              '  prod:\n'
              '    ssl_pinning: { pins: ["$one"] }\n',
        ),
      );
      await expectRefused(
        ws,
        contains('flavors.prod.ssl_pinning.pins: pin at least two keys'),
      );
    });

    test('a pin must be the base64 of 32 bytes', () async {
      final ws = workspace(
        manifest: demoManifest(
          flavors:
              'flavors:\n'
              '  dev:\n'
              '  staging:\n'
              '    ssl_pinning: { disabled: "no pins yet" }\n'
              '  prod:\n'
              '    ssl_pinning: { pins: ["not base64", "AAAA"] }\n',
        ),
      );
      final result = await run(ws, ['verify']);
      expect(result, exitsWith(1));
      expect(
        result.output,
        allOf(
          contains(
            'flavors.prod.ssl_pinning.pins[0]: expected the base64 of a '
            '32-byte SPKI SHA-256 hash',
          ),
          contains(
            'flavors.prod.ssl_pinning.pins[1]: expected the base64 of a '
            '32-byte SPKI SHA-256 hash',
          ),
        ),
      );
    });

    test('pins and disabled together are refused', () async {
      final ws = workspace(
        manifest: demoManifest(
          flavors:
              'flavors:\n'
              '  dev:\n'
              '  staging:\n'
              '    ssl_pinning: { disabled: "x", pins: ["a", "b"] }\n'
              '  prod:\n'
              '    ssl_pinning: { disabled: "no pins yet" }\n',
        ),
      );
      await expectRefused(
        ws,
        contains('flavors.staging.ssl_pinning: decide one of `pins:'),
      );
    });
  });

  group('V14 — a reason says why', () {
    for (final reason in ['TODO', 'tbd', 'TODO: decide', '', '   ']) {
      test('capability reason "$reason" is refused', () async {
        final ws = workspace(
          manifest: demoManifest(
            capabilities: capabilitiesWith(
              'splash: { state: absent, reason: "the native splash is kept through boot" }',
              'splash: { state: absent, reason: "$reason" }',
            ),
          ),
        );
        await expectRefused(
          ws,
          contains(
            '$manifestPath: capabilities.splash.reason: a reason is empty, '
            '`TODO` or `TBD` — say why the app has none, e.g. "the native '
            'splash is kept"',
          ),
        );
      });
    }

    test('a pin reason is held to the same rule', () async {
      final ws = workspace(
        manifest: demoManifest(
          flavors:
              'flavors:\n'
              '  dev:\n'
              '  staging:\n'
              '    ssl_pinning: { disabled: "no pins yet" }\n'
              '  prod:\n'
              '    ssl_pinning: { disabled: "TBD" }\n',
        ),
      );
      await expectRefused(
        ws,
        contains('flavors.prod.ssl_pinning.disabled: a reason is empty'),
      );
    });

    test('a reason that merely contains the word is fine', () async {
      final ws = workspace(
        manifest: demoManifest(
          capabilities: capabilitiesWith(
            'splash: { state: absent, reason: "the native splash is kept through boot" }',
            'splash: { state: absent, reason: "see the todo list in the wiki" }',
          ),
        ),
      );
      expect(await run(ws, ['sync']), exitsWith(0));
    });
  });

  group('V13 — the generated regions equal regeneration', () {
    Future<TempWorkspace> synced() async {
      final ws = workspace();
      expect(await run(ws, ['sync']), exitsWith(0));
      expect(await run(ws, ['verify']), exitsWith(0));
      return ws;
    }

    test(
      'a hand-edited facts region fails verify, and sync repairs it',
      () async {
        final ws = await synced();
        ws.write({
          profilePath: ws
              .read(profilePath)
              .replaceFirst('push: false,', 'push: true,'),
        });

        final verify = await run(ws, ['verify']);
        expect(verify, exitsWith(1));
        expect(verify.output, contains('out of date: $profilePath (facts)'));

        expect(await run(ws, ['sync']), exitsWith(0));
        expect(await run(ws, ['verify']), exitsWith(0));
        expect(ws.read(profilePath), contains('push: false,'));
      },
    );

    test('a deleted facts region fails verify naming the marker', () async {
      final ws = await synced();
      ws.write({
        profilePath: ws
            .read(profilePath)
            .replaceAll(RegExp(r'// composer:(managed|end):facts[^\n]*\n'), ''),
      });

      final verify = await run(ws, ['verify']);
      expect(verify, exitsWith(1));
      expect(verify.output, contains('has no `// composer:managed:facts'));
    });

    test('an edited entry point (the modules tail) fails verify', () async {
      final ws = await synced();
      ws.write({
        injectionPath: ws
            .read(injectionPath)
            .replaceFirst(
              'getIt.enableRegisteringMultipleInstancesOfOneType();',
              'getIt.allowReassignment = true;',
            ),
      });

      final verify = await run(ws, ['verify']);
      expect(verify, exitsWith(1));
      expect(verify.output, contains('out of date: $injectionPath (modules)'));

      expect(await run(ws, ['sync']), exitsWith(0));
      expect(
        ws.read(injectionPath),
        contains('getIt.enableRegisteringMultipleInstancesOfOneType();'),
      );
    });

    test('an edited report fails verify', () async {
      final ws = await synced();
      ws.write({
        readmePath: ws
            .read(readmePath)
            .replaceFirst('## demo — Demo App', '## demo'),
      });

      final verify = await run(ws, ['verify']);
      expect(verify, exitsWith(1));
      expect(verify.output, contains('out of date: $readmePath (report)'));
    });

    test(
      'changing the declaration without syncing is drift in all three',
      () async {
        final ws = await synced();
        ws.write({
          manifestPath: demoManifest(
            appBlock: 'app:\n  id: demo\n  name: Demo Renamed\n',
          ),
        });

        final verify = await run(ws, ['verify']);
        expect(verify, exitsWith(1));
        expect(verify.output, contains('out of date: $profilePath (facts)'));
        expect(verify.output, contains('out of date: $readmePath (report)'));
      },
    );

    test('hand text around a region survives sync', () async {
      final ws = workspace(
        extra: {
          readmePath:
              '# demo\n\nMy own notes above.\n\n'
              '<!-- composer:managed:report — generated from app_manifest.yaml -->\n'
              '<!-- composer:end:report -->\n\nAnd below.\n',
        },
      );
      expect(await run(ws, ['sync']), exitsWith(0));
      final readme = ws.read(readmePath);
      expect(readme, contains('My own notes above.'));
      expect(readme, contains('And below.'));
      expect(readme, contains('## demo — Demo App'));
    });
  });
}
