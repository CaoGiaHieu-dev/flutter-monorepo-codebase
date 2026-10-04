import 'dart:io';

import 'package:path/path.dart' as p;

/// What a committed native runner says about the app's flavors: the Android
/// `productFlavors` (and the application ID each yields) and the iOS flavor
/// schemes (and the bundle ID of each).
///
/// The manifest is the one declaration of an app's flavors (`flavors:`), but a
/// flavor is also a native fact — a Gradle `productFlavor`, an Xcode scheme
/// and build configuration pair — that Flutter's `--flavor` selects by name.
/// Nothing tied the two: deleting `staging:` from the manifest left the
/// Gradle flavor and `env.stg` behind, and the application IDs lived only in a
/// hand-written README table. composer reads the native files as text (it has
/// no Gradle or Xcode), strictly enough to compare names and to print the IDs,
/// and says so when it cannot read one.
class NativeFlavors {
  const NativeFlavors({
    this.android,
    this.androidFile,
    this.ios,
    this.iosSchemesDir,
    this.androidRunner = false,
    this.iosRunner = false,
    this.iosConfigurations = const {},
  });

  /// No committed runner says anything about flavors.
  const NativeFlavors.none()
    : android = null,
      androidFile = null,
      ios = null,
      iosSchemesDir = null,
      androidRunner = false,
      iosRunner = false,
      iosConfigurations = const {};

  /// The Gradle `productFlavors`, name -> application ID (`null` when the ID
  /// cannot be worked out); `null` when the Android runner declares none.
  final Map<String, String?>? android;

  /// Repo-relative-ish path of the Gradle file [android] was read from.
  final String? androidFile;

  /// The iOS flavor schemes, name -> bundle ID (`null` when it cannot be read);
  /// `null` when the iOS runner has no scheme beside `Runner`.
  final Map<String, String?>? ios;

  /// The directory the schemes were listed from.
  final String? iosSchemesDir;

  /// An Android runner is committed: `android/app/build.gradle(.kts)` exists.
  /// A bare `android/` folder is V6's business, not a runner V15 can read.
  final bool androidRunner;

  /// An iOS runner is committed: `ios/Runner.xcodeproj` exists.
  final bool iosRunner;

  /// The build configuration names of the Xcode project (`Debug-dev`,
  /// `Release-dev`, `Profile-dev`, `Debug`, ...), empty when the project cannot
  /// be read. Flutter's `--flavor <f>` needs `Debug-<f>`, `Release-<f>` and
  /// `Profile-<f>` beside the scheme named `<f>`.
  final Set<String> iosConfigurations;

  bool get isEmpty => android == null && ios == null;
}

/// Reads the native flavor declarations of the app at [appDir].
///
/// Only a runner that exists is read: an app with no `android/` folder yields
/// no Android flavors, which is not a problem — V6 owns whether a runner is
/// committed.
NativeFlavors readNativeFlavors(String appDir) {
  Map<String, String?>? android;
  String? androidFile;
  var androidRunner = false;
  for (final name in const ['build.gradle.kts', 'build.gradle']) {
    final file = File(p.join(appDir, 'android', 'app', name));
    if (!file.existsSync()) continue;
    androidRunner = true;
    androidFile = p.posix.join('android', 'app', name);
    android = parseGradleFlavors(file.readAsStringSync());
    break;
  }

  Map<String, String?>? ios;
  String? schemesDir;
  final xcodeproj = Directory(p.join(appDir, 'ios', 'Runner.xcodeproj'));
  final iosRunner = xcodeproj.existsSync();
  final pbxprojFile = File(p.join(xcodeproj.path, 'project.pbxproj'));
  final pbxproj = pbxprojFile.existsSync()
      ? pbxprojFile.readAsStringSync()
      : '';
  final schemes = Directory(
    p.join(appDir, 'ios', 'Runner.xcodeproj', 'xcshareddata', 'xcschemes'),
  );
  if (schemes.existsSync()) {
    schemesDir = p.posix.join(
      'ios',
      'Runner.xcodeproj',
      'xcshareddata',
      'xcschemes',
    );
    final names = <String>[
      for (final entity in schemes.listSync())
        if (entity is File && entity.path.endsWith('.xcscheme'))
          p.basenameWithoutExtension(entity.path),
    ]..sort();
    final flavors = names.where((n) => n != 'Runner').toList();
    if (flavors.isNotEmpty) {
      final ids = parseBundleIds(pbxproj);
      ios = {for (final name in flavors) name: ids[name]};
    }
  }

  return NativeFlavors(
    android: android,
    androidFile: androidFile,
    ios: ios,
    iosSchemesDir: schemesDir,
    androidRunner: androidRunner,
    iosRunner: iosRunner,
    iosConfigurations: parseBuildConfigurations(pbxproj),
  );
}

/// The names of the build configurations of an Xcode `project.pbxproj`
/// (`Debug`, `Debug-dev`, ...), from its `XCBuildConfiguration` objects.
Set<String> parseBuildConfigurations(String pbxproj) {
  final block = RegExp(
    r'isa = XCBuildConfiguration;(.*?)name = "?([\w-]+)"?;\s*\};',
    dotAll: true,
  );
  return {for (final m in block.allMatches(pbxproj)) m.group(2)!};
}

/// The `productFlavors` of a Gradle build script (Kotlin or Groovy DSL) and
/// the application ID each yields: its own `applicationId`, else the
/// `defaultConfig` one plus the flavor's `applicationIdSuffix`.
///
/// `null` when the script has no `productFlavors` block.
Map<String, String?>? parseGradleFlavors(String source) {
  final code = _withoutComments(source);
  final start = RegExp(r'\bproductFlavors\s*\{').firstMatch(code);
  if (start == null) return null;
  final close = _matchingBrace(code, start.end - 1);
  if (close == -1) return null;

  final block = code.substring(start.end, close);
  final outside = code.replaceRange(start.start, close + 1, '');
  final base = RegExp(
    r'''\bapplicationId\s*=?\s*["']([^"']+)["']''',
  ).firstMatch(outside)?.group(1);

  final flavors = <String, String?>{};
  final entry = RegExp(
    r'''(?:\b(?:create|register)\(\s*["'](\w+)["']\s*\)|(?<![\w."'])(\w+))\s*\{''',
  );
  var depth = 0;
  var i = 0;
  while (i < block.length) {
    final c = block[i];
    if (c == '{') {
      depth++;
    } else if (c == '}') {
      depth--;
    }
    if (depth == 0) {
      final m = entry.matchAsPrefix(block, i);
      if (m != null && (i == 0 || !_isWord(block[i - 1]))) {
        final name = m.group(1) ?? m.group(2)!;
        final open = m.end - 1;
        final end = _matchingBrace(block, open);
        if (end == -1) break;
        final body = block.substring(open + 1, end);
        flavors[name] = _applicationId(body, base);
        i = end + 1;
        continue;
      }
    }
    i++;
  }
  return flavors.isEmpty ? null : flavors;
}

String? _applicationId(String body, String? base) {
  final own = RegExp(
    r'''\bapplicationId\s*=?\s*["']([^"']+)["']''',
  ).firstMatch(body)?.group(1);
  if (own != null) return own;
  if (base == null) return null;
  final suffix = RegExp(
    r'''\bapplicationIdSuffix\s*=?\s*["']([^"']*)["']''',
  ).firstMatch(body)?.group(1);
  return '$base${suffix ?? ''}';
}

/// The `PRODUCT_BUNDLE_IDENTIFIER` of the app target for each flavor, from the
/// build configurations named `<Mode>-<flavor>` in an Xcode `project.pbxproj`;
/// a release configuration wins over a debug one. The test target
/// (`...RunnerTests`) is skipped.
Map<String, String> parseBundleIds(String pbxproj) {
  final byFlavor = <String, ({String id, bool release})>{};
  final block = RegExp(
    r'isa = XCBuildConfiguration;(.*?)name = "?([\w-]+)"?;\s*\};',
    dotAll: true,
  );
  for (final m in block.allMatches(pbxproj)) {
    final name = m.group(2)!;
    final dash = name.indexOf('-');
    if (dash == -1) continue;
    final mode = name.substring(0, dash);
    final flavor = name.substring(dash + 1);
    final id = RegExp(
      r'PRODUCT_BUNDLE_IDENTIFIER = "?([^";\s]+)"?;',
    ).firstMatch(m.group(1)!)?.group(1);
    if (id == null || id.endsWith('.RunnerTests')) continue;
    final release = mode == 'Release';
    final seen = byFlavor[flavor];
    if (seen == null || (release && !seen.release)) {
      byFlavor[flavor] = (id: id, release: release);
    }
  }
  return {for (final e in byFlavor.entries) e.key: e.value.id};
}

bool _isWord(String c) => RegExp(r'\w').hasMatch(c);

/// [source] without `//` and `/* */` comments. A `//` inside a string (a URL)
/// is kept: only a `//` not preceded by `:` starts a comment.
String _withoutComments(String source) => source
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
    .replaceAll(RegExp(r'(?<!:)//[^\n]*'), '');

/// The index of the `}` matching the `{` at [open], or -1.
int _matchingBrace(String text, int open) {
  var depth = 0;
  for (var i = open; i < text.length; i++) {
    if (text[i] == '{') depth++;
    if (text[i] == '}') {
      depth--;
      if (depth == 0) return i;
    }
  }
  return -1;
}
