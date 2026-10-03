import 'package:test/test.dart';

import '../composer/src/native_flavors.dart';
import '../composer/src/profile_summary.dart';
import 'support/composer_fixture.dart';
import 'support/tool_harness.dart';

/// What the apps layer says about an app beyond its manifest keys (RULE-64):
///
/// | Piece | Holds |
/// |:-:|:--|
/// | `native_flavors.dart` | reads the Gradle `productFlavors`, the Xcode flavor schemes and the IDs each yields |
/// | `profile_summary.dart` | reads which profile sections an app's `appProfile` sets |
/// | V11 | no env file exists for a flavor the manifest does not declare |
/// | V15 | the native flavors are the declared flavors |
/// | V16 | every DI group says why, and the named groups keep the canonical order |
/// | report | §1 prints the native IDs, §5 prints the effective profile values |
void main() {
  group('parseGradleFlavors', () {
    test('reads a Groovy build script: flavors, suffixes and own IDs', () {
      const gradle = '''
android {
    defaultConfig {
        applicationId "com.example.codebase"
    }
    flavorDimensions "env"
    productFlavors {
        dev {
            dimension "env"
            applicationIdSuffix ".dev"
        }
        staging {
            dimension "env"
            applicationId "com.example.other.stg"
        }
        prod {
            dimension "env"
        }
    }
}
''';
      expect(parseGradleFlavors(gradle), {
        'dev': 'com.example.codebase.dev',
        'staging': 'com.example.other.stg',
        'prod': 'com.example.codebase',
      });
    });

    test('reads the Kotlin DSL (`create("name")`) and ignores comments', () {
      const gradle = '''
android {
    defaultConfig { applicationId = "com.example.kts" }
    productFlavors {
        // create("legacy") { applicationIdSuffix = ".legacy" }
        create("dev") { applicationIdSuffix = ".dev" }
        create("prod") { dimension = "env" }
    }
}
''';
      expect(parseGradleFlavors(gradle), {
        'dev': 'com.example.kts.dev',
        'prod': 'com.example.kts',
      });
    });

    test('a script with no productFlavors says nothing', () {
      expect(parseGradleFlavors('android { defaultConfig { } }'), isNull);
    });
  });

  group('parseBundleIds', () {
    const pbxproj = '''
/* Begin XCBuildConfiguration section */
		AAA /* Debug-dev */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				PRODUCT_BUNDLE_IDENTIFIER = com.example.codebase.dev;
			};
			name = "Debug-dev";
		};
		BBB /* Release-dev */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				PRODUCT_BUNDLE_IDENTIFIER = com.example.codebase.dev.release;
			};
			name = "Release-dev";
		};
		CCC /* Debug-prod */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				PRODUCT_BUNDLE_IDENTIFIER = "com.example.codebase";
			};
			name = "Debug-prod";
		};
		DDD /* Debug-prod */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				PRODUCT_BUNDLE_IDENTIFIER = com.example.codebase.RunnerTests;
			};
			name = "Debug-prod";
		};
		EEE /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				PRODUCT_BUNDLE_IDENTIFIER = com.example.codebase;
			};
			name = Debug;
		};
/* End XCBuildConfiguration section */
''';

    test('a release configuration wins, the test target is skipped', () {
      expect(parseBundleIds(pbxproj), {
        'dev': 'com.example.codebase.dev.release',
        'prod': 'com.example.codebase',
      });
    });
  });

  group('parseProfileOverrides', () {
    test('an app that passes only its facts sets nothing', () {
      final read = parseProfileOverrides(
        'const AppProfile appProfile = AppProfile(facts: appFacts);',
      );
      expect(read.found, isTrue);
      expect(read.expressions, isEmpty);
    });

    test('reads the sections at the top level of the call, as written', () {
      final read = parseProfileOverrides('''
/// const AppProfile appProfile = AppProfile(facts: appFacts, theme: x);
const AppProfile appProfile = AppProfile(
  facts: appFacts, // not a section
  network: NetworkProfile(
    connectTimeout: Duration(seconds: 10),
    headers: {'x-app': 'kiosk'},
  ),
  locale: LocaleProfile(supported: ['vi'], fallback: 'vi'),
);
''');
      expect(read.expressions.keys, ['network', 'locale']);
      expect(
        read.expressions['network'],
        'NetworkProfile( connectTimeout: Duration(seconds: 10), '
        "headers: {'x-app': 'kiosk'}, )",
      );
      expect(read.sets('locale'), isTrue);
      expect(read.sets('display'), isFalse);
    });

    test('no AppProfile call is unknown, not "sets nothing"', () {
      final read = parseProfileOverrides('const x = 1;');
      expect(read.found, isFalse);
    });
  });

  group('the composed app', () {
    late CompiledTool tool;

    setUpAll(() async {
      tool = await CompiledTool.compile('tools/composer/composer.dart');
    });
    tearDownAll(() => tool.dispose());

    const manifestPath = 'apps/demo/app_manifest.yaml';

    Future<ToolRun> run(TempWorkspace ws, List<String> args) =>
        tool.run(args, workingDirectory: ws.root);

    Future<ToolRun> syncAndVerify(TempWorkspace ws) async {
      final synced = await run(ws, ['sync']);
      expect(synced, exitsWith(0));
      return run(ws, ['verify']);
    }

    TempWorkspace demo({
      Map<String, String> extra = const {},
      String? manifest,
    }) => TempWorkspace.create(
      demoWorkspaceFiles(manifest: manifest, extra: extra),
    );

    void expectRefused(ToolRun result, List<Pattern> parts) {
      expect(result, exitsWith(1));
      for (final part in parts) {
        expect(result.output, contains(part));
      }
    }

    const gradleAll = '''
android {
    defaultConfig { applicationId "com.example.demo" }
    productFlavors {
        dev { applicationIdSuffix ".dev" }
        staging { applicationIdSuffix ".stg" }
        prod { }
    }
}
''';

    group('V15 native flavors are the declared flavors', () {
      test('a runner naming exactly the declared flavors passes', () async {
        final ws = demo(
          extra: {'apps/demo/android/app/build.gradle': gradleAll},
        );
        expect(await syncAndVerify(ws), exitsWith(0));
      });

      test('a runner that names none says nothing', () async {
        final ws = demo(
          extra: {'apps/demo/android/app/build.gradle': 'android { }'},
        );
        expect(await syncAndVerify(ws), exitsWith(0));
      });

      test('a Gradle flavor the manifest dropped fails, naming both', () async {
        final ws = demo(
          extra: {
            'apps/demo/android/app/build.gradle': gradleAll.replaceFirst(
              'prod { }',
              'prod { }\n        qa { }',
            ),
          },
        );
        expectRefused(await syncAndVerify(ws), [
          '$manifestPath: flavors: apps/demo/android/app/build.gradle has a '
              'productFlavor named `qa`, which the manifest does not declare',
        ]);
      });

      test(
        'a declared flavor the runner lacks fails, naming the fix',
        () async {
          final ws = demo(
            extra: {
              'apps/demo/android/app/build.gradle': gradleAll.replaceFirst(
                '        staging { applicationIdSuffix ".stg" }\n',
                '',
              ),
            },
          );
          expectRefused(await syncAndVerify(ws), [
            '$manifestPath: flavors.staging: declared, but '
                'apps/demo/android/app/build.gradle has no productFlavor named '
                '`staging`',
            'or delete `staging:` from `flavors:`',
          ]);
        },
      );

      test('the report prints the application ID of each flavor', () async {
        final ws = demo(
          extra: {'apps/demo/android/app/build.gradle': gradleAll},
        );
        expect(await run(ws, ['sync']), exitsWith(0));

        final report = ws.read('apps/demo/README.md');
        expect(report, contains('Android application ID'));
        expect(report, contains('`com.example.demo.dev`'));
        expect(report, contains('`com.example.demo.stg`'));
        expect(report, contains('check V15'));
      });
    });

    group('V11 an env file for an undeclared flavor', () {
      test(
        'staging removed from flavors, env.stg left behind, fails',
        () async {
          final ws = demo(
            manifest: demoManifest(
              flavors:
                  'flavors:\n'
                  '  dev:\n'
                  '  prod:\n'
                  '    ssl_pinning: { disabled: "no SPKI pins provisioned yet" }\n',
            ),
            extra: {'apps/demo/env.stg': ''},
          );
          expectRefused(await syncAndVerify(ws), [
            'apps/demo/env.stg: flavor: belongs to the flavor `staging`, which '
                '$manifestPath does not declare under `flavors:`',
          ]);
        },
      );
    });

    group('V16 DI groups say why and keep the order', () {
      test('a group with no `why` fails, naming the group', () async {
        final ws = demo(manifest: demoManifest(why: ''));
        expectRefused(await syncAndVerify(ws), [
          '$manifestPath: di_groups[core].why: missing',
          '`no ordering constraint: <reason>`',
        ]);
      });

      test('a TODO `why` fails like any other empty reason', () async {
        final ws = demo(manifest: demoManifest(why: '    why: "TODO"\n'));
        expectRefused(await syncAndVerify(ws), [
          '$manifestPath: di_groups[core].why: is `TODO` or `TBD`',
        ]);
      });

      test('feature before domain fails with the canonical order', () async {
        final good = demoManifest();
        final swapped = good
            .replaceFirst(
              '  - name: domain\n'
                  '    phase: after\n'
                  '    from_modules: domain\n'
                  '    why: "interfaces first: features inject them"\n',
              '',
            )
            .replaceFirst(
              'modules:\n',
              '  - name: domain\n'
                  '    phase: after\n'
                  '    from_modules: domain\n'
                  '    why: "interfaces first: features inject them"\n'
                  'modules:\n',
            );
        final ws = demo(manifest: swapped);
        expectRefused(await syncAndVerify(ws), [
          '$manifestPath: di_groups: `feature` is listed before `domain`',
          'core → notifications → shell → ui → domain → data → feature → other',
        ]);
      });
    });

    group('report section 5 prints the effective profile values', () {
      test(
        'an app that sets nothing says so and lists every default',
        () async {
          final ws = demo();
          expect(await run(ws, ['sync']), exitsWith(0));

          final report = ws.read('apps/demo/README.md');
          expect(
            report,
            contains(
              'This app sets no profile section: every value below is '
              'the template default.',
            ),
          );
          expect(report, contains('design size $kDefaultDesignSize'));
          expect(report, contains('OS text-scale cap $kDefaultTextScaleMax'));
          expect(report, contains('timeout $kDefaultTimeout each'));
        },
      );

      test(
        'a tuned section is printed as written, the rest as default',
        () async {
          final base =
              demoWorkspaceFiles()['apps/demo/lib/app/app_profile.dart']!;
          final ws = demo(
            extra: {
              'apps/demo/lib/app/app_profile.dart': base.replaceFirst(
                'AppProfile(facts: appFacts)',
                'AppProfile(facts: appFacts, '
                    "locale: LocaleProfile(supported: ['vi'], fallback: 'vi'))",
              ),
            },
          );
          expect(await run(ws, ['sync']), exitsWith(0));

          final report = ws.read('apps/demo/README.md');
          expect(report, contains('**This app sets: `locale:`.**'));
          expect(
            report,
            contains(
              "**set** — `LocaleProfile(supported: ['vi'], fallback: 'vi')`",
            ),
          );
          expect(report, contains('| `network:` (`NetworkProfile`)'));
        },
      );
    });

    test(
      'the pin refusal on a platform that cannot pin offers a way out',
      () async {
        final ws = demo(
          manifest: demoManifest(
            platforms: 'platforms:\n  web: { runner: scaffold }\n',
            flavors:
                'flavors:\n'
                '  dev:\n'
                '  prod:\n'
                '    ssl_pinning:\n'
                '      pins:\n'
                '        - "${'A' * 43}="\n'
                '        - "${'B' * 42}E="\n',
          ),
        );
        final result = await run(ws, ['sync']);
        expect(result, exitsWith(1));
        expect(result.output, contains('declare android or ios'));
        expect(result.output, contains('gateway or proxy'));
        expect(result.output, contains('08_networking.md'));
      },
    );
  });
}
