import 'dart:io';

import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../shared/workspace.dart';

class MonorepoPackage {
  final String name;
  final String rootPath;

  /// Keys of `dependencies:`.
  final Set<String> dependencies;

  /// Keys of `dev_dependencies:`.
  final Set<String> devDependencies;

  /// The parsed `pubspec.yaml`, for checks that need more than the
  /// dependency names (e.g. `flutter_gen:` settings).
  final YamlMap? pubspec;

  MonorepoPackage({
    required this.name,
    required this.rootPath,
    required this.dependencies,
    this.devDependencies = const {},
    this.pubspec,
  });
}

class MonorepoHelper {
  static Map<String, MonorepoPackage>? _cachedPackages;

  /// The common start of every `check_unused_*.dart` script.
  ///
  /// Prints [usage] for `--help`/`-h` (exit 0) and rejects any other argument
  /// (exit 64). Then resolves the repository root from the script's own
  /// location — not from the working directory — makes it the working
  /// directory, and returns it as a POSIX path.
  ///
  /// The checks used to take `Directory.current` as the root: run from a
  /// subdirectory they found 0 packages and reported "no unused …" — a clean
  /// result for code they had never looked at. A root holding no package at
  /// all is therefore a failure (exit 1), never a pass.
  static String startCheck(List<String> args, {required String usage}) {
    if (args.contains('--help') || args.contains('-h')) {
      stdout.writeln(usage);
      exit(0);
    }
    if (args.isNotEmpty) {
      stderr.writeln('Unknown argument(s): ${args.join(' ')}');
      stderr.writeln('');
      stderr.writeln(usage);
      exit(64);
    }

    final root = repoRoot();
    Directory.current = root;
    if (getPackages(root).isEmpty) {
      stderr.writeln('[ERROR] No package (pubspec.yaml) found under $root.');
      exit(1);
    }
    return root;
  }

  /// The repository root as a POSIX path: the nearest ancestor of the running
  /// script holding both a `pubspec.yaml` and a `tools/` directory (the same
  /// test `tools/docs_check` uses). Falls back to the working directory when
  /// the script does not sit inside the repository.
  static String repoRoot() {
    var dir = File.fromUri(Platform.script).parent.absolute;
    while (true) {
      if (File(p.join(dir.path, 'pubspec.yaml')).existsSync() &&
          Directory(p.join(dir.path, 'tools')).existsSync()) {
        return p.posix.normalize(dir.path.replaceAll('\\', '/'));
      }
      final parent = dir.parent;
      if (parent.path == dir.path) {
        return p.posix.normalize(Directory.current.path.replaceAll('\\', '/'));
      }
      dir = parent;
    }
  }

  /// Scans the entire monorepo workspace for packages and builds a mapping.
  static Map<String, MonorepoPackage> getPackages(String projectRootPosix) {
    if (_cachedPackages != null) return _cachedPackages!;

    final packages = <String, MonorepoPackage>{};

    // Helper to parse a single pubspec
    void parsePubspec(String dirPath) {
      final file = File(p.posix.join(dirPath, 'pubspec.yaml'));
      if (!file.existsSync()) return;

      try {
        final content = file.readAsStringSync();
        final yaml = loadYaml(content) as YamlMap?;
        final name = yaml?['name'] as String?;
        if (name == null) return;

        Set<String> keysOf(Object? node) => {
          if (node is YamlMap)
            for (final key in node.keys)
              if (key is String) key,
        };

        packages[name] = MonorepoPackage(
          name: name,
          rootPath: dirPath,
          dependencies: keysOf(yaml?['dependencies']),
          devDependencies: keysOf(yaml?['dev_dependencies']),
          pubspec: yaml,
        );
      } catch (e) {
        stderr.writeln('Warning: Failed to parse pubspec.yaml at $dirPath: $e');
      }
    }

    // Discovery is a recursive scan for `pubspec.yaml` (the shared walk in
    // tools/shared/workspace.dart), not a fixed list of directories. The
    // previous version hardcoded `apps/mobile/`, `packages/core`,
    // `modules/*/feature`, `modules/*/data` and `modules/*/domain`, so moving
    // a package anywhere else made it invisible — and every consumer of this
    // helper (unused_checker, arch_check) would then report a clean result
    // for a package it had simply stopped looking at.
    for (final pubspec in findPubspecs(projectRootPosix)) {
      parsePubspec(p.posix.dirname(pubspec.path.replaceAll('\\', '/')));
    }
    // The repository root is a workspace anchor, not a package anyone depends
    // on; including it would make every path check relative to the wrong node.
    packages.removeWhere((_, pkg) => pkg.rootPath == projectRootPosix);

    _cachedPackages = packages;
    return packages;
  }

  /// Gets all Dart source files under all packages' lib directories.
  static Set<String> getAllDartFilesToScan(
    String projectRootPosix,
    List<Glob> excludedPatterns,
  ) {
    final allFiles = <String>{};
    final packages = getPackages(projectRootPosix);

    for (final pkg in packages.values) {
      final libDir = Directory(p.posix.join(pkg.rootPath, 'lib'));
      if (!libDir.existsSync()) continue;

      final files = libDir.listSync(recursive: true, followLinks: false);
      for (final file in files) {
        if (file is File && file.path.endsWith('.so')) {
          continue;
        }
        if (file is File && p.extension(file.path) == '.dart') {
          final normalized = p.posix.normalize(file.path.replaceAll('\\', '/'));
          final relPath = p.posix.relative(normalized, from: pkg.rootPath);

          bool isExcluded = excludedPatterns.any((pat) => pat.matches(relPath));
          if (!isExcluded) {
            allFiles.add(normalized);
          }
        }
      }
    }

    return allFiles;
  }

  /// Resolves an import/export/part path string to an absolute physical file path in the workspace.
  static String? resolveDirectivePath(
    String projectRootPosix,
    String currentFile,
    String pathString,
  ) {
    if (pathString.startsWith('dart:')) {
      return null;
    }

    final packages = getPackages(projectRootPosix);

    if (pathString.startsWith('package:')) {
      final parts = pathString.split('/');
      final packageName = parts[0].substring('package:'.length);
      final pkg = packages[packageName];
      if (pkg == null) return null; // External package

      final relPathInLib = parts.skip(1).join('/');
      return p.posix.normalize(p.posix.join(pkg.rootPath, 'lib', relPathInLib));
    }

    // Relative import
    final containingDir = p.posix.dirname(currentFile);
    return p.posix.normalize(p.posix.join(containingDir, pathString));
  }
}
