import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:test/test.dart';

import '../workspace_setup/firebase_stubs.dart';
import 'support/tool_harness.dart';

/// `configure.dart --stub-firebase` — the compile-only Firebase stand-ins CI
/// writes. Exercised through the library: the flag itself runs the whole
/// setup (`flutter clean`, codegen) first, which a temp workspace cannot.
void main() {
  const manifest = 'app:\n  id: mobile\n';
  const module = '''
import 'firebase_options_dev.dart' as dev;
import 'firebase_options_prod.dart' as prod;
import 'firebase_options_staging.dart' as stg;
''';
  const gradle = '''
plugins {
    id("com.android.application")
    id("com.google.gms.google-services")
}
android {
    signingConfigs {
        create("dev") { storeFile = file("x") }
        create("nightly") { storeFile = file("y") }
    }
    defaultConfig {
        applicationId = "com.example.codebase"
    }
    productFlavors {
        // DEEP_LINK_SCHEME is the scheme (`<scheme>://settings?tab=2`).
        create("dev") {
            dimension = "environment"
            applicationIdSuffix = ".dev"
            ndk { abiFilters += "arm64-v8a" }
        }
        create("staging") {
            applicationIdSuffix = ".stg"
        }
        create("prod") {
            // No suffix for prod
        }
    }
}
''';

  test('stubs every flavor the module imports and every Gradle flavor', () {
    final ws = TempWorkspace.create({
      'apps/mobile/app_manifest.yaml': manifest,
      'apps/mobile/lib/firebase/firebase_module.dart': module,
      'apps/mobile/android/app/build.gradle.kts': gradle,
    });
    final report = writeFirebaseStubs(ws.root);

    expect(report.written, [
      'apps/mobile/lib/firebase/firebase_options_dev.dart',
      'apps/mobile/lib/firebase/firebase_options_prod.dart',
      'apps/mobile/lib/firebase/firebase_options_staging.dart',
      'apps/mobile/android/app/src/dev/google-services.json',
      'apps/mobile/android/app/src/staging/google-services.json',
      'apps/mobile/android/app/src/prod/google-services.json',
    ]);
    expect(report.kept, isEmpty);
    expect(
      ws.read('apps/mobile/lib/firebase/firebase_options_dev.dart'),
      firebaseOptionsStub,
    );

    String packageOf(String flavor) {
      final json = jsonDecode(
        ws.read('apps/mobile/android/app/src/$flavor/google-services.json'),
      ) as Map<String, dynamic>;
      final client = (json['client'] as List).single as Map<String, dynamic>;
      return ((client['client_info'] as Map)['android_client_info']
              as Map)['package_name']
          as String;
    }

    // The signingConfigs `create("nightly")` is not a flavor, and the
    // nested `ndk { }` does not end dev's block early.
    expect(packageOf('dev'), 'com.example.codebase.dev');
    expect(packageOf('staging'), 'com.example.codebase.stg');
    expect(packageOf('prod'), 'com.example.codebase');
    expect(ws.exists('apps/mobile/android/app/src/nightly'), isFalse);
  });

  test('never overwrites a real file', () {
    final ws = TempWorkspace.create({
      'apps/mobile/app_manifest.yaml': manifest,
      'apps/mobile/lib/firebase/firebase_module.dart': module,
      'apps/mobile/lib/firebase/firebase_options_prod.dart': '// real\n',
      'apps/mobile/android/app/build.gradle.kts': gradle,
      'apps/mobile/android/app/src/dev/google-services.json': '{"real":1}',
    });
    final report = writeFirebaseStubs(ws.root);

    expect(report.kept, [
      'apps/mobile/lib/firebase/firebase_options_prod.dart',
      'apps/mobile/android/app/src/dev/google-services.json',
    ]);
    expect(report.written, hasLength(4));
    expect(
      ws.read('apps/mobile/lib/firebase/firebase_options_prod.dart'),
      '// real\n',
    );
    expect(
      ws.read('apps/mobile/android/app/src/dev/google-services.json'),
      '{"real":1}',
    );
  });

  test('an app without Firebase or Android gets nothing', () {
    final ws = TempWorkspace.create({
      'apps/admin/app_manifest.yaml': 'app:\n  id: admin\n',
      'apps/admin/lib/main.dart': '',
      'apps/tv/app_manifest.yaml': 'app:\n  id: tv\n',
      'apps/tv/android/app/build.gradle.kts':
          'android { defaultConfig { applicationId = "com.example.tv" } }',
    });
    final report = writeFirebaseStubs(ws.root);

    expect(report.written, isEmpty);
    expect(report.notes, [
      contains('admin: no lib/firebase/firebase_module.dart'),
      contains('admin: no android/'),
      contains('tv: no lib/firebase/firebase_module.dart'),
      contains('tv: android/app does not apply the Google Services plugin'),
    ]);
  });

  test('Groovy flavors, and an app with no flavors at all', () {
    expect(
      androidFlavorSuffixes('''
android {
  productFlavors {
    free { applicationIdSuffix ".free" }
    paid {}
  }
}'''),
      {'free': '.free', 'paid': ''},
    );
    expect(androidFlavorSuffixes('android { }'), isEmpty);

    final ws = TempWorkspace.create({
      'apps/solo/app_manifest.yaml': 'app:\n  id: solo\n',
      'apps/solo/android/app/build.gradle':
          'apply plugin: "com.google.gms.google-services"\n'
          'android { defaultConfig { applicationId "com.example.solo" } }\n',
    });
    expect(writeFirebaseStubs(ws.root).written, [
      'apps/solo/android/app/google-services.json',
    ]);
  });

  test('the app id is read from app: id: past comments and other keys', () {
    final ws = TempWorkspace.create({
      'apps/x/app_manifest.yaml':
          '# comment\napp:\n  # the id\n  kind: flutter\n  id: phone\n'
          'modules:\n  - { id: not_this }\n',
      'apps/x/lib/firebase/firebase_module.dart': module,
    });
    expect(writeFirebaseStubs(ws.root).written, hasLength(3));
    final bare = TempWorkspace.create({
      'apps/x/app_manifest.yaml': 'modules:\n  - { id: not_an_app }\n',
      'apps/x/lib/firebase/firebase_module.dart': module,
    });
    expect(writeFirebaseStubs(bare.root).written, isEmpty);
  });

  // configure.dart is what runs `pub get` on a fresh clone, so it must
  // compile before any package is fetched: nothing it reaches may import a
  // `package:` URI. (The one inside the stub is string content.)
  test('configure.dart reaches no package: import', () {
    final seen = <String>{};
    final pending = [p.join(repoRoot, 'tools/workspace_setup/configure.dart')];
    final directive = RegExp(
      r'''^(?:import|export)\s+['"]([^'"]+)['"]''',
      multiLine: true,
    );
    while (pending.isNotEmpty) {
      final file = p.normalize(pending.removeLast());
      if (!seen.add(file)) continue;
      // Triple-quoted strings dropped first: the stub's import is content.
      final source = File(file).readAsStringSync().replaceAll(
        RegExp(r"'''[\s\S]*?'''"),
        '',
      );
      for (final m in directive.allMatches(source)) {
        final uri = m.group(1)!;
        if (uri.startsWith('dart:')) continue;
        expect(uri, isNot(startsWith('package:')), reason: '$file imports it');
        pending.add(p.join(p.dirname(file), uri));
      }
    }
    expect(seen, hasLength(greaterThan(2)));
  });

  // One source of truth: the setup guide shows these stubs verbatim, so the
  // guide and what `--stub-firebase` writes cannot drift apart.
  for (final lang in ['en', 'vi']) {
    test('docs/$lang/getting-started/01_setup.md § 3.2 shows these stubs', () {
      final guide = File(
        p.join(repoRoot, 'docs/$lang/getting-started/01_setup.md'),
      ).readAsStringSync();
      expect(guide, contains('```dart\n$firebaseOptionsStub```'));
      expect(
        guide,
        contains(
          '```json\n${googleServicesStub('com.example.codebase.dev')}```',
        ),
      );
    });
  }

  test('a module importing no options by name falls back to the three', () {
    expect(dartOptionFlavors('// nothing'), defaultFlavors);
  });
}
