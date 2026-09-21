import 'dart:io';
import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

class MonorepoPackage {
  final String name;
  final String rootPath;
  final Set<String> dependencies;

  MonorepoPackage({
    required this.name,
    required this.rootPath,
    required this.dependencies,
  });
}

class MonorepoHelper {
  static Map<String, MonorepoPackage>? _cachedPackages;

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

        final deps = <String>{};
        final dependenciesNode = yaml?['dependencies'];
        if (dependenciesNode is YamlMap) {
          dependenciesNode.keys.forEach((k) {
            if (k is String) deps.add(k);
          });
        }

        packages[name] = MonorepoPackage(
          name: name,
          rootPath: dirPath,
          dependencies: deps,
        );
      } catch (e) {
        stderr.writeln('Warning: Failed to parse pubspec.yaml at $dirPath: $e');
      }
    }

    // Discovery is a recursive scan for `pubspec.yaml`, not a fixed list of
    // directories. The previous version hardcoded `app/`, `packages/core`,
    // `packages/features`, `packages/data` and `packages/domain`, so moving a
    // package anywhere else made it invisible — and every consumer of this
    // helper (unused_checker, arch_check) would then report a clean result for
    // a package it had simply stopped looking at.
    void walk(Directory dir) {
      for (final entity in dir.listSync(followLinks: false)) {
        final name = p.posix.basename(entity.path.replaceAll('\\', '/'));
        if (entity is Directory) {
          const skip = {
            '.git',
            '.dart_tool',
            'build',
            'ios',
            'android',
            'macos',
            'windows',
            'linux',
            'web',
            'node_modules',
          };
          if (skip.contains(name) || name.startsWith('.')) continue;
          walk(entity);
        } else if (entity is File && name == 'pubspec.yaml') {
          parsePubspec(p.posix.dirname(entity.path.replaceAll('\\', '/')));
        }
      }
    }

    walk(Directory(projectRootPosix));
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
