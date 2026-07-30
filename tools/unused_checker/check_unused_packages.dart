import 'dart:io';
import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;
import 'monorepo_helper.dart';
import 'output_formatter.dart';

final _alwaysAllowedPackages = <String>{
  'flutter',
  'flutter_localizations',
  'cupertino_icons',
  'intl',
  'flutter_svg',
  'firebase_core',
  'get_it',
  'injectable',
  'freezed_annotation',
  'json_annotation',
  'retrofit',
  'provider',
  'dio',
};

final _excludedSourceFilePatterns = <Glob>[
  Glob('lib/generated_plugin_registrant.dart'),
  Glob('lib/gen/**.dart'),
  Glob('lib/src/gen/**.dart'),
  Glob('lib/**.g.dart'),
  Glob('lib/**.freezed.dart'),
];

void main() async {
  OutputFormatter.printHeader(
    'Monorepo Unused Packages Detector',
    subtitle: 'Analyzing unused dependencies across all workspace packages',
  );

  final stopwatch = Stopwatch()..start();
  final projectRoot = Directory.current.path;
  final projectRootPosix = p.posix.normalize(projectRoot.replaceAll(r'\', '/'));

  // 1. Find all packages in workspace
  final packages = MonorepoHelper.getPackages(projectRootPosix);
  OutputFormatter.printInfo(
    'Found ${packages.length} packages to analyze.',
    icon: '📁',
  );

  int totalUnusedCount = 0;
  final packagesWithUnused = <String, List<String>>{};

  for (final pkg in packages.values) {
    final pkgName = pkg.name;
    final pkgRoot = pkg.rootPath;

    // Skip root-level or empty dependencies package
    if (pkg.dependencies.isEmpty) continue;

    // Get Dart files inside the entire workspace to check global usage
    final pkgFiles = getDartFilesForPackage(pkgRoot, projectRootPosix);

    // Find all package imports in this package
    final importedPackages = findImportedPackages(pkgFiles, pkg.dependencies);

    // Determine unused dependencies
    final unused = <String>[];
    for (final depName in pkg.dependencies) {
      if (!_alwaysAllowedPackages.contains(depName) &&
          !importedPackages.contains(depName)) {
        // Skip local packages unless they are completely unused
        // Wait, local packages are prefix-based or path-based, we treat them like any package!
        unused.add(depName);
      }
    }

    if (unused.isNotEmpty) {
      packagesWithUnused[pkgName] = unused;
      totalUnusedCount += unused.length;
    }
  }

  stopwatch.stop();
  stdout.writeln(
    '================================================================================',
  );
  stdout.writeln(
    '             Unused Package Check Results (${stopwatch.elapsed.inMilliseconds}ms)               ',
  );
  stdout.writeln(
    '================================================================================',
  );

  if (totalUnusedCount == 0) {
    stdout.writeln(
      '✅ Success! No unused packages found across all workspace modules.',
    );
    exit(0);
  } else {
    stdout.writeln(
      '⚠️ Found $totalUnusedCount potentially unused dependencies across ${packagesWithUnused.length} packages:',
    );

    for (final entry in packagesWithUnused.entries) {
      stdout.writeln('\n📦 Package: ${entry.key}');
      for (final unusedDep in entry.value) {
        stdout.writeln('  - $unusedDep');
      }
    }

    stdout.writeln('\nNotes:');
    stdout.writeln(
      '  - Dependencies are analyzed package-by-package against the package\'s own lib/ directory.',
    );
    stdout.writeln(
      '  - Common SDK and implicit packages are allowed automatically.',
    );
    exit(2);
  }
}

Set<String> getDartFilesForPackage(String pkgRoot, String projectRoot) {
  final files = <String>{};
  // Check only the local package directory
  final libDir = Directory(pkgRoot);
  if (!libDir.existsSync()) return files;

  final all = libDir.listSync(recursive: true, followLinks: false);
  for (final file in all) {
    if (file is File && file.path.endsWith('.dart')) {
      final normalized = p.posix.normalize(file.path.replaceAll('\\', '/'));
      if (normalized.contains('/lib/') ||
          normalized.contains('/bin/') ||
          normalized.contains('/test/')) {
        // Exclude generated files locally
        bool isExcluded = false;
        final rel = p.posix.relative(normalized, from: pkgRoot);
        isExcluded = _excludedSourceFilePatterns.any((pat) => pat.matches(rel));

        if (!isExcluded) {
          files.add(normalized);
        }
      }
    }
  }
  return files;
}

Set<String> findImportedPackages(Set<String> dartFiles, Set<String> declared) {
  final imported = <String>{};
  final importRegex = RegExp(
    r'''^\s*(?:import|export)\s+['"]package:([a-zA-Z0-9_]+)(?:/[^'"]*)?['"].*?;''',
    multiLine: true,
  );

  for (final file in dartFiles) {
    try {
      final content = File(file).readAsStringSync();
      final matches = importRegex.allMatches(content);
      for (final match in matches) {
        final pkg = match.group(1);
        if (pkg != null && declared.contains(pkg)) {
          imported.add(pkg);
        }
      }
    } catch (e) {
      // Ignore reading errors
    }
  }
  return imported;
}
