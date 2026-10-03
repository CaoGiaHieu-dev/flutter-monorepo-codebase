import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../composer/src/catalog.dart';
import '../composer/src/manifest_v2.dart';
import 'support/tool_harness.dart';

/// composer cannot import `platform_kernel` or `platform_app_shell` — it runs
/// before code generation, and the kernel's barrel pulls generated output — so
/// it *spells* the enums and reads the shell's contract catalog from source.
/// These tests are what keep the spelled copies equal to the originals:
///
/// - the vocabularies (`Flavor`, `AppPlatform`, `RunnerKind`, `SplashMode`) and
///   the one derived fact (`AppPlatform.canPinTls`);
/// - the catalog: every `ShellContract<` row is parsed, ids are unique, and the
///   split is the 8 required / 14 optional the report promises;
/// - the **dead-key guard**: every key of the parse table names a consumer that
///   really reads it — `app.kind` was a key nothing read, and that class of bug
///   must not recur;
/// - `PlatformFacts.today()` — the one place a default exists twice — equals
///   the table composer derives from.
void main() {
  String read(String relative) =>
      File(p.join(repoRoot, relative)).readAsStringSync();

  /// The constants of `enum <name> { a, b; ... }` in [source], comments
  /// stripped.
  List<String> enumValues(String source, String name) {
    final code = source
        .split('\n')
        .where((line) => !line.trimLeft().startsWith('//'))
        .join('\n');
    final match = RegExp('enum $name\\s*\\{([^;}]*)').firstMatch(code);
    expect(match, isNotNull, reason: 'enum $name not found');
    return [
      for (final part in match!.group(1)!.split(','))
        if (part.trim().isNotEmpty) part.trim(),
    ];
  }

  group('the spelled vocabularies equal the kernel enums', () {
    final platform = read(
      'platform/foundation/kernel/lib/src/profile/app_platform.dart',
    );
    final facts = read(
      'platform/foundation/kernel/lib/src/profile/platform_facts.dart',
    );
    final flavor = read('platform/foundation/kernel/lib/src/flavor.dart');

    test('Flavor', () {
      expect(kFlavorNames, enumValues(flavor, 'Flavor'));
    });

    test('AppPlatform', () {
      expect(kPlatformNames, enumValues(platform, 'AppPlatform'));
    });

    test('RunnerKind', () {
      expect(kRunnerKinds, enumValues(facts, 'RunnerKind'));
    });

    test('SplashMode', () {
      expect(kSplashModes, enumValues(facts, 'SplashMode'));
    });

    test('OrientationPolicy, spelled snake_case in the manifest', () {
      String snake(String name) => name.replaceAllMapped(
        RegExp('[A-Z]'),
        (m) => '_${m.group(0)!.toLowerCase()}',
      );
      expect(kOrientationPolicies, [
        for (final v in enumValues(facts, 'OrientationPolicy')) snake(v),
      ]);
      // Every spelling maps onto the constant composer emits.
      expect(
        [for (final v in kOrientationPolicies) orientationConstant(v)],
        enumValues(facts, 'OrientationPolicy'),
      );
      expect(kDefaultOrientation, kOrientationPolicies.first);
    });

    test('the desktop platforms', () {
      final match = RegExp(
        r'bool get isDesktop =>([^;]*);',
      ).firstMatch(platform);
      expect(match, isNotNull);
      final names = {
        for (final m in RegExp(r'this == (\w+)').allMatches(match!.group(1)!))
          m.group(1)!,
      };
      expect(kDesktopPlatforms, names);
    });

    test('the platforms that can pin TLS', () {
      final match = RegExp(
        r'bool get canPinTls =>([^;]*);',
      ).firstMatch(platform);
      expect(match, isNotNull);
      final names = {
        for (final m in RegExp(r'this == (\w+)').allMatches(match!.group(1)!))
          m.group(1)!,
      };
      expect(kPinnablePlatforms, names);
    });
  });

  group('the shell contract catalog', () {
    final source = read(
      'platform/shell/app_shell/lib/src/composition/shell_contracts.dart',
    );
    final catalog = parseCatalogSource(source);

    test('every ShellContract<> row is parsed', () {
      final rows = RegExp(r'ShellContract<(\w+)>\(').allMatches(source).length;
      expect(catalog.entries, hasLength(rows));
      expect(rows, greaterThan(0));
    });

    test('ids are unique', () {
      final ids = [for (final e in catalog.entries) e.id];
      expect(ids.toSet(), hasLength(ids.length));
    });

    test('8 required rows, 14 optional ones, a bundle of four', () {
      expect(catalog.requiredRows, hasLength(8));
      expect(catalog.optional, hasLength(14));
      expect(catalog.membersOf('session'), hasLength(4));
    });

    test(
      'every row says where it is looked up and what happens without it',
      () {
        for (final e in catalog.entries) {
          expect(e.consumer, contains(':'), reason: e.id);
          expect(e.whenAbsent, isNotEmpty, reason: e.id);
        }
      },
    );

    test('the optional ids an app declares are the manifest keys', () {
      expect(
        catalog.optionalKeys,
        containsAll(['session', 'routes', 'tabs', 'splash', 'analytics']),
      );
      expect(catalog.optionalKeys, isNot(contains('session_state')));
      expect(catalog.declarableKeys, contains('session_state'));
    });
  });

  group('the dead-key guard', () {
    for (final key in kManifestKeys) {
      test('${key.key} is read by ${key.consumer}', () {
        final file = File(p.join(repoRoot, key.consumer));
        expect(file.existsSync(), isTrue, reason: '${key.consumer} is gone');
        expect(
          file.readAsStringSync(),
          contains(key.reads),
          reason:
              '`${key.key}` names `${key.consumer}` as its reader, but the '
              'file no longer mentions `${key.reads}` — a key nothing reads '
              'is the `app.kind` bug',
        );
      });
    }

    test('no key is listed twice', () {
      final keys = [for (final k in kManifestKeys) k.key];
      expect(keys.toSet(), hasLength(keys.length));
    });
  });

  group('PlatformFacts.today() equals the derived defaults', () {
    final facts = read(
      'platform/foundation/kernel/lib/src/profile/platform_facts.dart',
    );
    final today = RegExp(
      r'const PlatformFacts\.today\(\)(.*?);',
      dotAll: true,
    ).firstMatch(facts)!.group(1)!;

    String field(String name) => RegExp(
      '$name = ([\\w.]+)',
    ).firstMatch(today)!.group(1)!;

    test('the orientation, deep links and push composer derives', () {
      // composer: orientation `phonesPortrait`, deep links on, push on when
      // the notifications package is composed and supports the platform.
      expect(field('orientation'), 'OrientationPolicy.phonesPortrait');
      expect(field('deepLinks'), 'true');
      expect(field('push'), 'true');
    });

    test(
      'the Dart splash composer derives when capability splash is provided',
      () {
        expect(field('splash'), 'SplashMode.dart');
      },
    );

    test('the runner folder is committed', () {
      expect(field('runner'), 'RunnerKind.committed');
    });
  });
}
