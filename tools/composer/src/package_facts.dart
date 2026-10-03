import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'manifest_v2.dart';

/// What a composed package says about itself in its own `pubspec.yaml`, in two
/// keys pub accepts and validates nothing about (so composer does):
///
/// ```yaml
/// platforms: [android, ios, macos, web]    # where the package works
/// composition:
///   app_provides:                          # what the app must register for it
///     FirebaseOptions:
///       per_flavor: true
///       hint: "apps/<id>/lib/firebase/firebase_module.dart ..."
/// ```
///
/// Both are read by the app report. `platforms:` is also what the report names
/// when it says what blocks a platform the app does not declare.

/// One thing a package needs the app to register.
class AppProvides {
  const AppProvides({
    required this.type,
    required this.perFlavor,
    required this.hint,
  });

  /// The Dart type the app registers (`FirebaseOptions`).
  final String type;

  /// An `@Environment('<flavor>')` registration for every declared flavor.
  final bool perFlavor;

  /// Where and how, in a sentence. Not checked.
  final String hint;
}

/// A package's facts.
class PackageFacts {
  const PackageFacts({
    required this.name,
    required this.platforms,
    required this.appProvides,
  });

  final String name;

  /// The platforms the package works on, in canonical order; null when the
  /// package declares no restriction.
  final List<String>? platforms;

  final List<AppProvides> appProvides;

  /// Whether the package works on [platform].
  bool supports(String platform) =>
      platforms == null || platforms!.contains(platform);
}

/// Reads [packageDir]'s pubspec. [rel] is the pubspec's repo-relative path and
/// each problem is added to [problems] as `<rel>: <key>: <problem>`.
PackageFacts readPackageFacts(
  String name,
  String packageDir,
  String rel,
  List<String> problems,
) {
  final file = File(p.posix.join(packageDir, 'pubspec.yaml'));
  Object? doc;
  try {
    doc = loadYaml(file.readAsStringSync());
  } on YamlException {
    doc = null; // reported by the caller as invalid YAML
  }
  if (doc is! YamlMap) {
    return PackageFacts(name: name, platforms: null, appProvides: const []);
  }

  List<String>? platforms;
  final raw = doc['platforms'];
  if (raw != null) {
    final names = <String>[];
    final items = switch (raw) {
      YamlList() => raw.nodes.map((n) => n.value).toList(),
      YamlMap() => raw.keys.toList(),
      _ => null,
    };
    if (items == null) {
      problems.add(
        '$rel: platforms: expected a list of platform names, got '
        '${describeValue(raw)}',
      );
    } else {
      for (final item in items) {
        if (item is String && kPlatformNames.contains(item)) {
          names.add(item);
        } else {
          problems.add(
            '$rel: platforms: expected one of ${kPlatformNames.join(', ')}, '
            'got ${describeValue(item)}',
          );
        }
      }
      platforms = [
        for (final platform in kPlatformNames)
          if (names.contains(platform)) platform,
      ];
    }
  }

  final provides = <AppProvides>[];
  final composition = doc['composition'];
  if (composition is YamlMap) {
    final rawProvides = composition['app_provides'];
    if (rawProvides is YamlMap) {
      for (final entry in rawProvides.entries) {
        final type = entry.key;
        final value = entry.value;
        if (type is! String || value is! YamlMap) {
          problems.add(
            '$rel: composition.app_provides: expected `<Type>: { per_flavor, '
            'hint }`, got ${describeValue(value)}',
          );
          continue;
        }
        final hint = value['hint'];
        provides.add(
          AppProvides(
            type: type,
            perFlavor: value['per_flavor'] == true,
            hint: hint is String ? hint : '',
          ),
        );
      }
    } else if (rawProvides != null) {
      problems.add(
        '$rel: composition.app_provides: expected a map, got '
        '${describeValue(rawProvides)}',
      );
    }
  }

  return PackageFacts(name: name, platforms: platforms, appProvides: provides);
}
