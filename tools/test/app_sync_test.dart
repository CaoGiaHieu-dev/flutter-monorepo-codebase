import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../arch_check/platform_forks.dart';
import '../composer/src/catalog.dart';
import '../composer/src/manifest_v2.dart';
import '../composer/src/package_facts.dart';
import '../composer/src/profile_summary.dart';
import '../composer/src/report.dart';
import 'support/tool_harness.dart';

/// composer cannot import `platform_kernel` or `platform_app_shell` — it runs
/// before code generation, and the kernel's barrel pulls generated output — so
/// it *spells* the enums and reads the shell's contract catalog from source.
/// These tests are what keep the spelled copies equal to the originals:
///
/// - the vocabularies (`Flavor`, `AppPlatform`, `RunnerKind`, `SplashMode`) and
///   the one derived fact (`AppPlatform.canPinTls`);
/// - the catalog: every `ShellContract<` row is parsed, ids are unique, and the
///   split is the 7 required / 14 optional the report promises;
/// - the **dead-key guard**: every key of the parse table names a consumer that
///   really reads it — `app.kind` was a key nothing read, and that class of bug
///   must not recur;
/// - `PlatformFacts.today()` — the one place a default exists twice — equals
///   the table composer derives from;
/// - `WindowClass` (the kernel's spelling) equals `core_responsive`'s
///   `WindowSizeClass`;
/// - the package facts composer checks (`platforms:`, `composition.app_provides`)
///   are the ones the shipped packages declare, and every R17 allow-list entry
///   names a file that exists.
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

    test('the profile defaults the report prints are the kernel\'s', () {
      final display = read(
        'platform/foundation/kernel/lib/src/profile/display_profile.dart',
      );
      final network = read(
        'platform/foundation/kernel/lib/src/profile/network_profile.dart',
      );
      expect(
        display,
        contains(
          'this.designSize = const SizeSpec(${kDefaultDesignSize.replaceAll(' x ', ', ')})',
        ),
      );
      expect(display, contains('this.textScaleMax = $kDefaultTextScaleMax,'));
      expect(
        display,
        contains(
          'this.phoneMaxShortestSide = ${kDefaultPhoneMax.split(' ').first},',
        ),
      );
      expect(
        RegExp(r'Timeout = const Duration\(seconds: (\d+)\)')
            .allMatches(network)
            .map((m) => '${m.group(1)} s')
            .toSet(),
        {kDefaultTimeout},
      );
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
      'platform/shell/app_shell/lib/src/utils/shell_contract_constants.dart',
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

    test('7 required rows, 14 optional ones, a bundle of four', () {
      expect(catalog.requiredRows, hasLength(7));
      expect(catalog.optional, hasLength(14));
      expect(catalog.membersOf('session'), hasLength(4));
    });

    test(
      'every row says where it is looked up and what happens without it',
      () {
        for (final e in catalog.entries) {
          expect(e.consumer, endsWith('.dart'), reason: e.id);
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

  group('the docs quote the catalog as it is', () {
    // docs_check proves a path exists, never that an identifier or a count
    // does: the catalog was once quoted as `kShellContracts`, 22 rows, 8
    // required, after it had become `SHELL_CONTRACTS`, 21 rows, 7 required.
    final catalog = parseCatalogSource(
      read(
        'platform/shell/app_shell/lib/src/utils/shell_contract_constants.dart',
      ),
    );

    /// Every hand-written Markdown file that may quote the catalog; the
    /// history log records what was true when it was written, so it is out.
    final docs =
        <String>[
          for (final entity in Directory(repoRoot).listSync(recursive: true))
            if (entity is File && entity.path.endsWith('.md'))
              p.relative(entity.path, from: repoRoot),
        ].where((path) {
          final parts = p.split(path);
          return !path.startsWith(p.join('docs', 'history')) &&
              !parts.any(
                (part) =>
                    part == 'build' ||
                    part == '.dart_tool' ||
                    part == 'node_modules' ||
                    part.startsWith('.') &&
                        part != '.claude' &&
                        part != '.agents' &&
                        part != '.github',
              );
        }).toList();

    test('nobody names a catalog constant that does not exist', () {
      final stale = [
        for (final path in docs)
          if (read(path).contains('kShellContracts')) path,
      ];
      expect(stale, isEmpty, reason: 'say `SHELL_CONTRACTS`: $stale');
    });

    test('a quoted row count is the real one', () {
      final counts = <RegExp, int>{
        RegExp(r'(\d+)-row (?:contract )?catalog'): catalog.entries.length,
        RegExp(r'(\d+) rows? —'): catalog.entries.length,
        RegExp(r'(\d+) (?:\*\*)?required(?:\*\*)? rows'):
            catalog.requiredRows.length,
        RegExp(r'(\d+) dòng (?:\*\*)?bắt buộc'): catalog.requiredRows.length,
        RegExp(r'(\d+) (?:\*\*)?optional(?:\*\*)? rows'):
            catalog.optional.length,
        RegExp(r'(\d+) dòng (?:\*\*)?tuỳ chọn'): catalog.optional.length,
      };
      final wrong = <String>[];
      for (final path in docs) {
        final text = read(path);
        for (final MapEntry(key: pattern, value: real) in counts.entries) {
          for (final m in pattern.allMatches(text)) {
            if (int.parse(m.group(1)!) != real) {
              wrong.add('$path: "${m.group(0)}" (the catalog has $real)');
            }
          }
        }
      }
      expect(wrong, isEmpty);
    });
  });

  group('the dead-key guard', () {
    for (final key in kManifestKeys) {
      test('${key.key} is read by ${key.consumer}', () {
        final file = File(p.join(repoRoot, key.consumer));
        expect(file.existsSync(), isTrue, reason: '${key.consumer} is gone');
        // A use, not a name: `name` is also the field's own declaration, so a
        // bare identifier proves nothing about a reader. The guard asks for a
        // member access or a call, which only code that *uses* the value has.
        expect(
          key.reads,
          matches(RegExp(r'[.(]')),
          reason:
              '`${key.key}`: `reads` must be a use-site expression '
              '(`facts.name`, `platformFacts.splash`), not a field name',
        );
        expect(
          file.readAsStringSync(),
          contains(key.reads),
          reason:
              '`${key.key}` names `${key.consumer}` as its reader, but the '
              'file no longer contains `${key.reads}` — a key nothing reads '
              'is the `app.kind` bug',
        );
      });
    }

    test('a key only composer reads says so, and nothing else does', () {
      final reportOnly = [
        for (final key in kManifestKeys)
          if (key.reportOnly) key.key,
      ];
      expect(reportOnly, ['platforms.<p>.runner']);
      for (final key in kManifestKeys.where((k) => k.reportOnly)) {
        expect(key.consumer, startsWith('tools/composer/'));
      }
      // No runtime package reads `PlatformFacts.runner`: if one starts to,
      // this list is stale.
      final runtime =
          [
            for (final entity in Directory(
              p.join(repoRoot, 'platform'),
            ).listSync(recursive: true))
              if (entity is File &&
                  entity.path.endsWith('.dart') &&
                  !entity.path.contains('/test/') &&
                  !entity.path.contains('.dart_tool') &&
                  !entity.path.contains('/build/'))
                entity,
          ].where(
            (f) =>
                RegExp(r'(?<!this)\.runner\b').hasMatch(f.readAsStringSync()),
          );
      expect(
        runtime.map((f) => p.relative(f.path, from: repoRoot)),
        isEmpty,
        reason: '`.runner` is read at runtime: drop `reportOnly` from it',
      );
    });

    test('the pubspec keys composer checks have a reader, too', () {
      // `platforms:` and `composition.app_provides` are not manifest keys, so
      // the table above does not list them; the file that reads them does.
      final reader = read('tools/composer/src/package_facts.dart');
      expect(reader, contains("doc['platforms']"));
      expect(reader, contains("composition['app_provides']"));
      // And two checks consume what it reads.
      final checks = read('tools/composer/src/checks.dart');
      expect(checks, contains('facts.supports('), reason: 'V7');
      expect(checks, contains('appProvides'), reason: 'V10');
    });

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

  group('WindowClass equals core_responsive WindowSizeClass', () {
    test('by name and order', () {
      final kernel = enumValues(
        read('platform/foundation/kernel/lib/src/profile/display_profile.dart'),
        'WindowClass',
      );
      final responsive = enumValues(
        read('platform/ui/responsive/lib/src/adaptive/window_size_class.dart'),
        'WindowSizeClass',
      );
      expect(kernel, responsive);
    });
  });

  group('the package facts composer checks', () {
    PackageFacts facts(String name, String dir) {
      final problems = <String>[];
      final result = readPackageFacts(
        name,
        p.join(repoRoot, dir),
        '$dir/pubspec.yaml',
        problems,
      );
      expect(problems, isEmpty);
      return result;
    }

    test(
      'core_notifications: no Windows or Linux, FirebaseOptions per flavor',
      () {
        final notifications = facts(
          'core_notifications',
          'platform/infra/notifications',
        );
        expect(notifications.platforms, ['android', 'ios', 'web', 'macos']);
        expect(notifications.supports('windows'), isFalse);
        expect(notifications.supports('linux'), isFalse);
        final needs = notifications.appProvides;
        expect(needs.map((n) => n.type), ['FirebaseOptions']);
        expect(needs.single.perFlavor, isTrue);
      },
    );

    test('core_database: no web, because drift/native needs dart:ffi', () {
      final database = facts('core_database', 'platform/infra/database');
      expect(database.supports('web'), isFalse);
      expect(database.platforms, [
        'android',
        'ios',
        'windows',
        'macos',
        'linux',
      ]);
    });

    test('every declared platform is a name composer knows', () {
      // A typo in a pubspec would make `supports()` silently false.
      for (final dir
          in Directory(p.join(repoRoot, 'platform'))
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => p.basename(f.path) == 'pubspec.yaml')
              .map((f) => f.parent.path)) {
        final problems = <String>[];
        readPackageFacts('x', dir, '$dir/pubspec.yaml', problems);
        expect(problems, isEmpty, reason: dir);
      }
    });
  });

  group('the R17 allow-list', () {
    test('names files that exist, each with a reason', () {
      for (final entry in kPlatformForkAllowList.entries) {
        expect(
          File(p.join(repoRoot, entry.key)).existsSync(),
          isTrue,
          reason: '${entry.key} is allow-listed but gone',
        );
      }
      expect(allowListProblems(kPlatformForkAllowList), isEmpty);
    });

    test('the policy fork itself is the first entry', () {
      expect(
        kPlatformForkAllowList.keys.first,
        endsWith('config/platform_resolver.dart'),
      );
    });
  });

  group('what `describe --catalog` lists', () {
    test('every problem code is one the kernel or the shell reports', () {
      final sources =
          read('platform/foundation/kernel/lib/src/profile/app_profile.dart') +
          read(
            'platform/shell/app_shell/lib/src/composition/composition_check.dart',
          ) +
          read('platform/shell/app_shell/lib/src/bootstrap.dart');
      for (final problem in kBootProblems) {
        expect(
          sources,
          contains("'${problem.id}'"),
          reason: '${problem.id} is listed but no source reports it',
        );
      }
      // And no code the sources report is left out of the list.
      final reported = {
        for (final m in RegExp(r"'([PC]\d\d)'").allMatches(sources))
          m.group(1)!,
      };
      expect({for (final problem in kBootProblems) problem.id}, reported);
    });

    test(
      'every check V1 to V17 is listed once, and composer implements it',
      () {
        expect(
          [for (final check in kComposerChecks) check.id],
          [for (var i = 1; i <= 17; i++) 'V$i'],
        );
        final implementation =
            read('tools/composer/src/checks.dart') +
            read('tools/composer/src/manifest_v2.dart') +
            read('tools/composer/composer.dart');
        for (final check in kComposerChecks) {
          expect(
            implementation,
            anyOf(
              contains('${check.id} '),
              contains('${check.id}\n'),
              contains('${check.id},'),
              contains('${check.id}.'),
              contains('${check.id}:'),
              contains('(${check.id}'),
              contains('${check.id})'),
            ),
            reason: '${check.id} is listed but no composer source names it',
          );
        }
      },
    );
  });
}
