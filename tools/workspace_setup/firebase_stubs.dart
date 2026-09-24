import 'dart:io';

// dart:io ONLY. configure.dart imports this, and configure.dart is what runs
// `pub get` on a fresh clone — a package import here would stop it compiling
// before the step that fetches that package.

/// Compile-only Firebase stand-ins for a checkout with no Firebase project —
/// what `configure.dart --stub-firebase` writes, and the one place their
/// content lives. CI's jobs call that flag instead of carrying a heredoc
/// each, and `docs/en/getting-started/01_setup.md` § 3.2 shows the same
/// content.
///
/// Nothing here is a real configuration. The Dart options make the app
/// **compile** (analysis and unit tests never initialise Firebase); the
/// `google-services.json` lets the Google Services Gradle plugin finish
/// `process<Flavor>DebugGoogleServices`. Anything Firebase-backed at runtime
/// (push notifications, the FCM token) does not work with them.
///
/// A file that already exists is never touched — real options restored by a
/// workflow, or written by `flutterfire configure`, always win.

/// The stub `firebase_options_<flavor>.dart`. Byte-identical to the block in
/// `docs/en/getting-started/01_setup.md` § 3.2.
const String firebaseOptionsStub = '''
// CI-only stub. Not a real Firebase configuration: analysis and unit
// tests never initialise Firebase, they only need this to compile.
// Generate the real file with `flutterfire configure`.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform => const FirebaseOptions(
    apiKey: 'ci-stub',
    appId: 'ci-stub',
    messagingSenderId: 'ci-stub',
    projectId: 'ci-stub',
  );
}
''';

/// The stub `google-services.json` for the Android application ID
/// [packageName] — the flavor's `applicationId` + `applicationIdSuffix`,
/// which the Google Services plugin requires it to match.
String googleServicesStub(String packageName) =>
    '''
{
  "project_info": {
    "project_number": "000000000000",
    "project_id": "local-stub"
  },
  "client": [
    {
      "client_info": {
        "mobilesdk_app_id": "1:000000000000:android:0000000000000000",
        "android_client_info": {
          "package_name": "$packageName"
        }
      },
      "api_key": [
        { "current_key": "local-stub" }
      ]
    }
  ],
  "configuration_version": "1"
}
''';

/// The flavors used when a file names none: the template's three.
const List<String> defaultFlavors = ['dev', 'staging', 'prod'];

/// What [writeFirebaseStubs] did, as repo-relative `/` paths.
class FirebaseStubReport {
  final List<String> written = [];
  final List<String> kept = [];

  /// Apps skipped, each with the reason (no Firebase module, no Android).
  final List<String> notes = [];
}

/// Writes every missing stub under [root] and reports what it did.
///
/// * `firebase_options_<flavor>.dart` beside each app's
///   `lib/firebase/firebase_module.dart`, one per `firebase_options_*.dart`
///   the module imports (an app without that module does not use Firebase
///   and gets none).
/// * `android/app/src/<flavor>/google-services.json` for each app whose
///   `android/app/build.gradle(.kts)` applies the Google Services plugin,
///   one per product flavor, its `package_name` read from the same file.
FirebaseStubReport writeFirebaseStubs(String root) {
  final report = FirebaseStubReport();

  void writeIfAbsent(String relative, String content) {
    final file = File('$root/$relative');
    if (file.existsSync()) {
      report.kept.add(relative);
      return;
    }
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
    report.written.add(relative);
  }

  for (final app in _apps(root)) {
    final module = File(
      '$root/${app.dir}/lib/firebase/firebase_module.dart',
    );
    if (module.existsSync()) {
      for (final flavor in dartOptionFlavors(module.readAsStringSync())) {
        writeIfAbsent(
          '${app.dir}/lib/firebase/firebase_options_$flavor.dart',
          firebaseOptionsStub,
        );
      }
    } else {
      report.notes.add(
        '${app.id}: no lib/firebase/firebase_module.dart — does not use '
        'Firebase, no Dart options stubbed',
      );
    }

    final gradle =
        [
              'build.gradle.kts',
              'build.gradle',
            ]
            .map((f) => File('$root/${app.dir}/android/app/$f'))
            .where(
              (f) => f.existsSync(),
            )
            .firstOrNull;
    if (gradle == null) {
      report.notes.add('${app.id}: no android/ — no google-services.json');
      continue;
    }
    final script = gradle.readAsStringSync();
    if (!script.contains('com.google.gms.google-services')) {
      report.notes.add(
        '${app.id}: android/app does not apply the Google Services plugin — '
        'no google-services.json',
      );
      continue;
    }
    final applicationId = RegExp(
      r'''applicationId\s*=?\s*["']([^"']+)["']''',
    ).firstMatch(script)?.group(1);
    if (applicationId == null) {
      report.notes.add(
        '${app.id}: no applicationId in ${gradle.uri.pathSegments.last} — '
        'no google-services.json',
      );
      continue;
    }
    final flavors = androidFlavorSuffixes(script);
    if (flavors.isEmpty) {
      writeIfAbsent(
        '${app.dir}/android/app/google-services.json',
        googleServicesStub(applicationId),
      );
    }
    flavors.forEach((flavor, suffix) {
      writeIfAbsent(
        '${app.dir}/android/app/src/$flavor/google-services.json',
        googleServicesStub('$applicationId$suffix'),
      );
    });
  }
  return report;
}

/// Every app under [root] — a directory holding an `app_manifest.yaml` —
/// sorted by id: the same marker and skip list as
/// `tools/shared/app_locator.dart`, whose `package:yaml` this file cannot use.
List<({String id, String dir})> _apps(String root) {
  final out = <({String id, String dir})>[];
  const skip = {'.git', '.dart_tool', 'build', 'packages', 'modules'};
  final idPattern = RegExp(
    r'''^app:\s*\n(?:[ \t]+.*\n|[ \t]*#.*\n|\s*\n)*?[ \t]+id:\s*["']?([\w-]+)''',
    multiLine: true,
  );
  final rootPath = Directory(root).absolute.path;
  void walk(Directory dir) {
    for (final e in dir.listSync(followLinks: false)) {
      final name = e.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (e is Directory) {
        if (skip.contains(name)) continue;
        walk(e);
      } else if (e is File && name == 'app_manifest.yaml') {
        final id = idPattern.firstMatch(e.readAsStringSync())?.group(1);
        if (id == null) continue;
        final dir = e.parent.absolute.path
            .substring(rootPath.length)
            .replaceAll('\\', '/')
            .replaceFirst(RegExp(r'^/+'), '');
        out.add((id: id, dir: dir));
      }
    }
  }

  walk(Directory(root));
  out.sort((a, b) => a.id.compareTo(b.id));
  return out;
}

/// The flavors whose options [firebaseModule] imports
/// (`import 'firebase_options_dev.dart' as dev;` -> `dev`), in file order;
/// [defaultFlavors] when it imports none by that name.
List<String> dartOptionFlavors(String firebaseModule) {
  final flavors = [
    for (final m in RegExp(
      r'''import\s+['"]firebase_options_(\w+)\.dart['"]''',
    ).allMatches(firebaseModule))
      m.group(1)!,
  ];
  return flavors.isEmpty ? defaultFlavors : flavors;
}

/// Each product flavor in the Gradle [script] mapped to its
/// `applicationIdSuffix` (`''` when it sets none), in declaration order.
///
/// Only the `productFlavors { ... }` block is read — `signingConfigs` uses
/// the same `create("dev")` shape.
Map<String, String> androidFlavorSuffixes(String script) {
  final start = RegExp(r'productFlavors\s*\{').firstMatch(script);
  if (start == null) return const {};
  final out = <String, String>{};
  final header = RegExp(
    r'''(?:create\s*\(\s*["'](\w+)["']\s*\)|\b(\w+))\s*$''',
  );
  final suffix = RegExp(r'''applicationIdSuffix\s*=?\s*["']([^"']*)["']''');
  // Walk the block, tracking depth: a `{` at depth 1 opens one flavor, named
  // by the text just before it (`create("dev")` in Kotlin, `dev` in Groovy);
  // anything nested deeper belongs to that flavor.
  var depth = 1;
  var segmentStart = start.end;
  String? current;
  var bodyStart = 0;
  for (var i = start.end; i < script.length && depth > 0; i++) {
    final c = script[i];
    if (c == '{') {
      if (depth == 1) {
        final name = header.firstMatch(script.substring(segmentStart, i));
        current = name == null ? null : (name.group(1) ?? name.group(2));
        bodyStart = i + 1;
      }
      depth++;
    } else if (c == '}') {
      depth--;
      if (depth == 1) {
        if (current != null) {
          final body = script.substring(bodyStart, i);
          out[current] = suffix.firstMatch(body)?.group(1) ?? '';
        }
        current = null;
        segmentStart = i + 1;
      }
    }
  }
  return out;
}
