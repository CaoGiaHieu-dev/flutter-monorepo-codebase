import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../composer/src/manifest_v2.dart' show kPinnablePlatforms;
import 'support/composer_fixture.dart';
import 'support/tool_harness.dart';

/// `tools/composer/composer.dart` — what a platform enables:
/// `platforms.<p>.{push, deep_links, secure_storage, orientation, window}` and
/// check V8.
///
/// | Check | Holds |
/// |:-:|:--|
/// | V1 | the keys' types and vocabulary; an unknown platform key is refused |
/// | V8 | `push: true` needs `core_notifications` composed, the platform in its `push_platforms` and a committed runner; `deep_links: true` needs a committed runner and is refused on the web; `window` only on a desktop platform |
///
/// A key written in the manifest reaches the generated facts as `// manifest`
/// and replaces the derived default; a key left out keeps it, and the first
/// derivation rule that matches says why in the comment above it (the table
/// of `derivePlatforms`, row by row below). Every refusal names the file and
/// the key and writes nothing.
void main() {
  late CompiledTool tool;

  setUpAll(() async {
    tool = await CompiledTool.compile('tools/composer/composer.dart');
  });
  tearDownAll(() => tool.dispose());

  const manifestPath = 'apps/demo/app_manifest.yaml';
  const profilePath = 'apps/demo/lib/app/app_profile.dart';
  const readmePath = 'apps/demo/README.md';

  /// `core_notifications` as the repository declares it: it links
  /// everywhere, and Firebase Messaging delivers on four platforms.
  const notificationsPubspec =
      'name: core_notifications\n'
      'composition:\n'
      '  push_platforms: [android, ios, macos, web]\n';

  /// An app on [platforms] (the YAML block), optionally composing
  /// `core_notifications`.
  TempWorkspace workspace(
    String platforms, {
    bool notifications = false,
    Set<String> without = const {},
    Map<String, String> extra = const {},
  }) {
    // A platform that can pin needs a decision per flavor; one that cannot
    // refuses it.
    final canPin = kPinnablePlatforms.any(platforms.contains);
    var manifest = demoManifest(
      platforms: platforms,
      flavors: canPin ? kFlavors : 'flavors:\n  dev:\n  staging:\n  prod:\n',
    );
    if (notifications) {
      manifest = manifest.replaceFirst(
        '  - name: shell\n',
        '  - name: notifications\n'
            '    phase: after\n'
            '    packages: [core_notifications]\n'
            '    why: "FirebaseOptions come from the app, after core"\n'
            '  - name: shell\n',
      );
    }
    final files = demoWorkspaceFiles(
      manifest: manifest,
      extra: {
        if (notifications) ...{
          'platform/infra/notifications/pubspec.yaml': notificationsPubspec,
          'platform/infra/notifications/lib/di/module.dart': diModule(),
        },
        ...extra,
      },
    )..removeWhere((path, _) => without.contains(path));
    return TempWorkspace.create(files);
  }

  Future<ToolRun> run(TempWorkspace ws, List<String> args) =>
      tool.run(args, workingDirectory: ws.root);

  Future<void> expectRefused(TempWorkspace ws, Matcher message) async {
    final result = await run(ws, ['verify']);
    expect(result, exitsWith(1));
    expect(result.output, message);
    expect(
      ws.read('pubspec.yaml'),
      isNot(contains('apps/demo')),
      reason: 'a refused manifest must not write anything',
    );
  }

  const desktop =
      'platforms:\n'
      '  windows:\n'
      '    runner: scaffold\n'
      '    orientation: free\n'
      '    deep_links: false\n'
      '    window: { initial: [1280, 800], min: [800, 600] }\n'
      '  linux: { runner: scaffold }\n';

  final noRunner = {'apps/demo/android/README.txt'};

  /// The generated facts of [platform] alone, from `AppPlatform.<platform>`
  /// to the next platform (or the end of the map).
  String factsOf(String facts, String platform) {
    final start = facts.indexOf('AppPlatform.$platform: PlatformFacts(');
    expect(start, greaterThan(-1), reason: '$platform has no facts');
    final end = facts.indexOf('AppPlatform.', start + 1);
    return facts.substring(start, end == -1 ? facts.length : end);
  }

  group('a key left out keeps its derived default', () {
    test('and says where it came from', () async {
      final ws = workspace(kPlatforms);
      expect(await run(ws, ['sync']), exitsWith(0));

      final facts = ws.read(profilePath);
      expect(
        facts,
        contains(
          '// default: the committed runner registers its links\n'
          '      deepLinks: true,',
        ),
      );
      expect(
        facts,
        contains(
          '// default\n      secureStorage: SecureStoragePolicy.required,',
        ),
      );
      expect(
        facts,
        contains(
          '// default\n      orientation: OrientationPolicy.phonesPortrait,',
        ),
      );
      expect(facts, isNot(contains('window:')));
    });
  });

  group('a key written in the manifest replaces it', () {
    test('and is emitted as `// manifest`', () async {
      final ws = workspace(desktop, without: noRunner);
      expect(await run(ws, ['sync']), exitsWith(0));

      final facts = ws.read(profilePath);
      final windows = facts.substring(
        facts.indexOf('AppPlatform.windows'),
        facts.indexOf('AppPlatform.linux'),
      );
      expect(
        windows,
        contains('// manifest\n      orientation: OrientationPolicy.free,'),
      );
      expect(windows, contains('// manifest\n      deepLinks: false,'));
      expect(
        windows,
        contains(
          '// manifest\n'
          '      window: WindowFacts(\n'
          '        initial: SizeSpec(1280, 800),\n'
          '        min: SizeSpec(800, 600),\n'
          '      ),',
        ),
      );
      // The other platform of the same app is untouched.
      final linux = facts.substring(facts.indexOf('AppPlatform.linux'));
      expect(
        linux,
        contains(
          '// derived: a generated runner registers no URL scheme\n'
          '      deepLinks: false,',
        ),
      );
      expect(linux, isNot(contains('window:')));
      expect(await run(ws, ['verify']), exitsWith(0));
    });

    test('a window with no minimum emits only `initial`', () async {
      final ws = workspace(
        'platforms:\n'
        '  linux:\n'
        '    runner: scaffold\n'
        '    window: { initial: [1024.5, 768] }\n',
        without: noRunner,
      );
      expect(await run(ws, ['sync']), exitsWith(0));

      final facts = ws.read(profilePath);
      expect(facts, contains('initial: SizeSpec(1024.5, 768),'));
      expect(facts, isNot(contains('min:')));
    });

    test('push: false overrides the derived on', () async {
      final ws = workspace(
        'platforms:\n  android: { runner: committed, push: false }\n',
        notifications: true,
      );
      expect(await run(ws, ['sync']), exitsWith(0));

      expect(ws.read(profilePath), contains('// manifest\n      push: false,'));
    });

    test(
      'push: true with the package composed and supporting it is fine',
      () async {
        final ws = workspace(
          'platforms:\n  android: { runner: committed, push: true }\n',
          notifications: true,
        );
        expect(await run(ws, ['sync']), exitsWith(0));

        expect(
          ws.read(profilePath),
          contains('// manifest\n      push: true,'),
        );
      },
    );

    test('the report shows the effective value and its source', () async {
      final ws = workspace(desktop, without: noRunner);
      expect(await run(ws, ['sync']), exitsWith(0));

      final readme = ws.read(readmePath);
      expect(readme, contains('| Orientation | TLS pinning | Window |'));
      expect(readme, contains('free (manifest)'));
      expect(readme, contains('off (manifest)'));
      expect(
        readme,
        contains(
          '1280 x 800, min 800 x 600 (manifest; needs the `configureWindow` hook)',
        ),
      );
    });

    test('the generated facts are a fixed point of dart format', () async {
      final ws = workspace(desktop, without: noRunner);
      expect(await run(ws, ['sync']), exitsWith(0));
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
  });

  group('the derivation, row by row: the first rule that matches wins', () {
    /// Syncs an app on [platforms] and returns the facts of [platform].
    Future<String> derived(
      String platforms,
      String platform, {
      bool notifications = false,
      Map<String, String> extra = const {},
    }) async {
      final ws = workspace(
        platforms,
        notifications: notifications,
        without: platforms.contains('android:') ? const {} : noRunner,
        extra: extra,
      );
      expect(await run(ws, ['sync']), exitsWith(0));
      return factsOf(ws.read(profilePath), platform);
    }

    String push(String why, {required bool on}) => '// $why\n      push: $on,';
    String links(String why, {required bool on}) =>
        '// $why\n      deepLinks: $on,';

    group('push', () {
      test('1. the manifest', () async {
        expect(
          await derived(
            'platforms:\n  android: { runner: committed, push: false }\n',
            'android',
            notifications: true,
          ),
          contains(push('manifest', on: false)),
        );
      });

      test('2. off where core_notifications is not composed', () async {
        expect(
          await derived(kPlatforms, 'android'),
          contains(
            push('derived: core_notifications is not composed', on: false),
          ),
        );
      });

      test('3. off on the web, committed or not', () async {
        expect(
          await derived(
            'platforms:\n  web: { runner: committed }\n',
            'web',
            notifications: true,
            extra: {'apps/demo/web/index.html': '<html>\n'},
          ),
          contains(
            push(
              'derived: no messaging service worker is shipped for web',
              on: false,
            ),
          ),
        );
      });

      test('4. off on a generated runner, even where it would push', () async {
        expect(
          await derived(
            'platforms:\n  macos: { runner: scaffold }\n',
            'macos',
            notifications: true,
          ),
          contains(
            push(
              'derived: a generated runner carries no push setup',
              on: false,
            ),
          ),
        );
      });

      test('5. off where push_platforms lacks the platform', () async {
        expect(
          await derived(
            'platforms:\n  linux: { runner: committed }\n',
            'linux',
            notifications: true,
            extra: {'apps/demo/linux/README.txt': 'runner\n'},
          ),
          contains(
            push(
              'derived: Firebase Messaging does not deliver on linux',
              on: false,
            ),
          ),
        );
      });

      test('6. otherwise on', () async {
        expect(
          await derived(
            'platforms:\n  android: { runner: committed }\n',
            'android',
            notifications: true,
          ),
          contains(
            push(
              'derived: core_notifications is composed and pushes on android',
              on: true,
            ),
          ),
        );
      });

      test('without push_platforms a package pushes wherever it links', () {
        // `pushes()` falls back to `platforms:`: an adopter's own push
        // package that predates the key still derives as before.
        final ws = workspace(
          'platforms:\n  linux: { runner: committed }\n',
          notifications: true,
          without: noRunner,
          extra: {
            'apps/demo/linux/README.txt': 'runner\n',
            'platform/infra/notifications/pubspec.yaml':
                'name: core_notifications\n',
          },
        );
        return run(ws, ['sync']).then((result) {
          expect(result, exitsWith(0));
          expect(
            factsOf(ws.read(profilePath), 'linux'),
            contains(
              push(
                'derived: core_notifications is composed and pushes on linux',
                on: true,
              ),
            ),
          );
        });
      });
    });

    group('deep_links', () {
      test('1. the manifest', () async {
        expect(
          await derived(
            'platforms:\n  android: { runner: committed, deep_links: false }\n',
            'android',
          ),
          contains(links('manifest', on: false)),
        );
      });

      test('2. off on the web', () async {
        expect(
          await derived('platforms:\n  web: { runner: scaffold }\n', 'web'),
          contains(
            links(
              'derived: the address bar is the deep link; the router reads it',
              on: false,
            ),
          ),
        );
      });

      test('3. off on a generated runner', () async {
        expect(
          await derived(
            'platforms:\n  android: { runner: scaffold }\n',
            'android',
            extra: {'apps/demo/android/README.txt': 'generated\n'},
          ),
          contains(
            links(
              'derived: a generated runner registers no URL scheme',
              on: false,
            ),
          ),
        );
      });

      test('4. off on a committed desktop runner', () async {
        expect(
          await derived(
            'platforms:\n  windows: { runner: committed }\n',
            'windows',
            extra: {'apps/demo/windows/README.txt': 'runner\n'},
          ),
          contains(
            links(
              'derived: register the URL scheme in the runner, then set it '
              'true',
              on: false,
            ),
          ),
        );
      });

      test('5. on for a committed Android or iOS runner', () async {
        expect(
          await derived(kPlatforms, 'android'),
          contains(
            links(
              'default: the committed runner registers its links',
              on: true,
            ),
          ),
        );
      });
    });

    group('secure_storage', () {
      test('the manifest', () async {
        expect(
          await derived(
            'platforms:\n  linux: { runner: scaffold, secure_storage: required }\n',
            'linux',
          ),
          contains(
            '// manifest\n      secureStorage: SecureStoragePolicy.required,',
          ),
        );
        expect(
          await derived(
            'platforms:\n  android: { runner: committed, secure_storage: memory_fallback }\n',
            'android',
          ),
          contains(
            '// manifest\n      secureStorage: SecureStoragePolicy.memoryFallback,',
          ),
        );
      });

      test('memory_fallback on linux', () async {
        expect(
          await derived('platforms:\n  linux: { runner: scaffold }\n', 'linux'),
          contains(
            '// derived: a Linux session may run no Secret Service\n'
            '      secureStorage: SecureStoragePolicy.memoryFallback,',
          ),
        );
      });

      test('required elsewhere, by default', () async {
        for (final platform in ['windows', 'macos', 'web']) {
          expect(
            await derived(
              'platforms:\n  $platform: { runner: scaffold }\n',
              platform,
            ),
            contains(
              '// default\n      secureStorage: SecureStoragePolicy.required,',
            ),
            reason: platform,
          );
        }
      });

      test('a policy outside the two is refused', () async {
        final ws = workspace(
          'platforms:\n  linux: { runner: scaffold, secure_storage: wipe }\n',
          without: noRunner,
        );
        await expectRefused(
          ws,
          contains(
            '$manifestPath: platforms.linux.secure_storage: expected required '
            'or memory_fallback, got a string (`wipe`)',
          ),
        );
      });

      test('the report has a secure-storage column', () async {
        final ws = workspace(
          'platforms:\n  linux: { runner: scaffold }\n',
          without: noRunner,
        );
        expect(await run(ws, ['sync']), exitsWith(0));
        final readme = ws.read(readmePath);
        expect(readme, contains('| Deep links | Secure storage |'));
        expect(
          readme,
          contains(
            '| memory_fallback (derived: a Linux session may run no Secret '
            'Service) |',
          ),
        );
      });
    });
  });

  group('V1 — vocabulary and shape', () {
    test('an orientation outside the four', () async {
      final ws = workspace(
        'platforms:\n  android: { runner: committed, orientation: sideways }\n',
      );
      await expectRefused(
        ws,
        contains(
          '$manifestPath: platforms.android.orientation: expected one of '
          'phones_portrait, free, portrait, landscape, got a string (`sideways`)',
        ),
      );
    });

    test('push and deep_links are booleans', () async {
      final ws = workspace(
        'platforms:\n  android: { runner: committed, push: yes please, deep_links: 1 }\n',
      );
      final result = await run(ws, ['verify']);
      expect(result, exitsWith(1));
      expect(
        result.output,
        allOf(
          contains(
            '$manifestPath: platforms.android.push: expected true or false',
          ),
          contains(
            '$manifestPath: platforms.android.deep_links: expected true or false',
          ),
        ),
      );
    });

    test('an unknown platform key lists the known ones', () async {
      final ws = workspace(
        'platforms:\n  android: { runner: committed, notifications: false }\n',
      );
      await expectRefused(
        ws,
        contains(
          '$manifestPath: platforms.android.notifications: unknown key — '
          'expected runner, splash, push, deep_links, secure_storage, '
          'orientation, window',
        ),
      );
    });

    for (final (label, window, problem) in [
      (
        'a window with no initial size',
        '{ min: [800, 600] }',
        'platforms.linux.window.initial: expected `[width, height]`',
      ),
      (
        'a size with one side',
        '{ initial: [1280] }',
        'platforms.linux.window.initial: expected `[width, height]`',
      ),
      (
        'a size with a non-positive side',
        '{ initial: [1280, 0] }',
        'platforms.linux.window.initial: expected `[width, height]`',
      ),
      (
        'a minimum larger than the initial size',
        '{ initial: [800, 600], min: [1280, 600] }',
        'platforms.linux.window.min: the minimum size must not exceed the '
            'initial size',
      ),
      (
        'an unknown window key',
        '{ initial: [800, 600], max: [900, 700] }',
        'platforms.linux.window.max: unknown key — expected initial, min',
      ),
      (
        'a window that is not a map',
        '[800, 600]',
        'platforms.linux.window: expected',
      ),
    ]) {
      test(label, () async {
        final ws = workspace(
          'platforms:\n  linux: { runner: scaffold, window: $window }\n',
          without: noRunner,
        );
        await expectRefused(ws, contains('$manifestPath: $problem'));
      });
    }
  });

  group('V8 — a switch needs what it switches on', () {
    test(
      'push: true with core_notifications not composed is refused',
      () async {
        final ws = workspace(
          'platforms:\n  android: { runner: committed, push: true }\n',
        );
        await expectRefused(
          ws,
          contains(
            '$manifestPath: platforms.android.push: push is on, but '
            'core_notifications is not composed',
          ),
        );
      },
    );

    test(
      'push: true where Firebase Messaging does not deliver is refused, '
      'naming push_platforms',
      () async {
        final ws = workspace(
          'platforms:\n  windows: { runner: committed, push: true }\n',
          notifications: true,
          without: noRunner,
          extra: {'apps/demo/windows/README.txt': 'runner\n'},
        );
        await expectRefused(
          ws,
          contains(
            '$manifestPath: platforms.windows.push: push is on, but '
            'core_notifications does not push on windows (its '
            'composition.push_platforms lists android, ios, macos, web; '
            'Firebase Messaging has no windows implementation) — set '
            '`push: false`, or delete the key',
          ),
        );
      },
    );

    test('push: true on a generated runner is refused', () async {
      final ws = workspace(
        'platforms:\n  macos: { runner: scaffold, push: true }\n',
        notifications: true,
        without: noRunner,
      );
      await expectRefused(
        ws,
        contains(
          '$manifestPath: platforms.macos.push: push is on, but the macos '
          'runner is generated (`runner: scaffold`) and carries none of the '
          'native push setup (google-services.json, the aps-environment '
          'entitlement, web/firebase-messaging-sw.js) — commit the runner, '
          'set it up, then switch push on; or delete the key',
        ),
      );
    });

    test(
      'push: true on a committed runner in push_platforms is fine',
      () async {
        final ws = workspace(
          'platforms:\n  macos: { runner: committed, push: true }\n',
          notifications: true,
          without: noRunner,
          extra: {'apps/demo/macos/README.txt': 'runner\n'},
        );
        expect(await run(ws, ['sync']), exitsWith(0));
      },
    );

    test('deep_links: true on a generated runner is refused', () async {
      final ws = workspace(
        'platforms:\n  linux: { runner: scaffold, deep_links: true }\n',
        without: noRunner,
      );
      await expectRefused(
        ws,
        contains(
          '$manifestPath: platforms.linux.deep_links: deep links are on, but '
          'the linux runner is generated (`runner: scaffold`) and registers '
          'no URL scheme or app link, so no link would arrive — commit the '
          'runner and register them (docs/en/guides/13_app_composition.md '
          '§ 7, "Deep links on a committed runner"), or delete the key',
        ),
      );
    });

    test('deep_links: true on the web is refused, committed or not', () async {
      for (final runner in ['scaffold', 'committed']) {
        final ws = workspace(
          'platforms:\n  web: { runner: $runner, deep_links: true }\n',
          without: noRunner,
          extra: {
            if (runner == 'committed') 'apps/demo/web/index.html': '<html>\n',
          },
        );
        await expectRefused(
          ws,
          contains(
            '$manifestPath: platforms.web.deep_links: on the web the address '
            'bar is the deep link and the router already reads it; app_links '
            "would route the page's own URL a second time — delete the key",
          ),
        );
      }
    });

    test('deep_links: true on a committed desktop runner is fine', () async {
      final ws = workspace(
        'platforms:\n  linux: { runner: committed, deep_links: true }\n',
        without: noRunner,
        extra: {'apps/demo/linux/README.txt': 'runner\n'},
      );
      expect(await run(ws, ['sync']), exitsWith(0));
      expect(
        factsOf(ws.read(profilePath), 'linux'),
        contains('// manifest\n      deepLinks: true,'),
      );
    });

    test('push: false needs nothing', () async {
      final ws = workspace(
        'platforms:\n  windows: { runner: scaffold, push: false }\n',
        without: noRunner,
      );
      expect(await run(ws, ['sync']), exitsWith(0));
    });

    test('a window on a phone platform is refused', () async {
      final ws = workspace(
        'platforms:\n'
        '  android: { runner: committed, window: { initial: [800, 600] } }\n',
      );
      await expectRefused(
        ws,
        contains(
          '$manifestPath: platforms.android.window: only a desktop platform '
          '(windows, macos, linux) has a resizable window',
        ),
      );
    });

    test('a window on the web is refused too', () async {
      final ws = workspace(
        'platforms:\n'
        '  web: { runner: scaffold, window: { initial: [800, 600] } }\n',
        without: noRunner,
      );
      await expectRefused(ws, contains('platforms.web.window: only a desktop'));
    });

    test('every problem is reported at once, and nothing is written', () async {
      final ws = workspace(
        'platforms:\n'
        '  android: { runner: committed, push: true }\n'
        '  web: { runner: scaffold, window: { initial: [800, 600] } }\n',
      );
      final result = await run(ws, ['sync']);

      expect(result, exitsWith(1));
      expect(result.output, contains('platforms.android.push'));
      expect(result.output, contains('platforms.web.window'));
      expect(
        File(p.join(ws.root, profilePath)).readAsStringSync(),
        isNot(contains('PlatformFacts(')),
        reason: 'V8 refuses before anything is generated',
      );
    });
  });
}
