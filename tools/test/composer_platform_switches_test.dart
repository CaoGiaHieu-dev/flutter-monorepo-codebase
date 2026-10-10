import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../composer/src/manifest_v2.dart' show kPinnablePlatforms;
import 'support/composer_fixture.dart';
import 'support/tool_harness.dart';

/// `tools/composer/composer.dart` — what a platform enables:
/// `platforms.<p>.{push, deep_links, orientation, window}` and check V8.
///
/// | Check | Holds |
/// |:-:|:--|
/// | V1 | the four keys' types and vocabulary; an unknown platform key is refused |
/// | V8 | `push: true` needs `core_notifications` composed and supporting the platform; `window` only on a desktop platform |
///
/// A key written in the manifest reaches the generated facts as `// manifest`
/// and replaces the derived default; a key left out keeps it. Every refusal
/// names the file and the key and writes nothing.
void main() {
  late CompiledTool tool;

  setUpAll(() async {
    tool = await CompiledTool.compile('tools/composer/composer.dart');
  });
  tearDownAll(() => tool.dispose());

  const manifestPath = 'apps/demo/app_manifest.yaml';
  const profilePath = 'apps/demo/lib/app/app_profile.dart';
  const readmePath = 'apps/demo/README.md';

  const notificationsPubspec =
      'name: core_notifications\n'
      'platforms:\n'
      '  android:\n'
      '  ios:\n'
      '  macos:\n'
      '  web:\n';

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

  group('a key left out keeps its derived default', () {
    test('and says where it came from', () async {
      final ws = workspace(kPlatforms);
      expect(await run(ws, ['sync']), exitsWith(0));

      final facts = ws.read(profilePath);
      expect(facts, contains('// default\n      deepLinks: true,'));
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
      expect(linux, contains('// default\n      deepLinks: true,'));
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
          'expected runner, splash, push, deep_links, orientation, window',
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
      'push: true on a platform the package does not support is refused',
      () async {
        final ws = workspace(
          'platforms:\n  windows: { runner: scaffold, push: true }\n',
          notifications: true,
          without: noRunner,
        );
        await expectRefused(
          ws,
          contains(
            '$manifestPath: platforms.windows.push: push is on, but '
            'core_notifications does not support windows (its pubspec '
            '`platforms:` lists android, ios, web, macos)',
          ),
        );
      },
    );

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
