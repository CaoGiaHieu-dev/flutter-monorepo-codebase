import 'dart:collection';
import 'dart:io';
import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;
import 'monorepo_helper.dart';

// --- Configuration ---
// Files matching these patterns (relative to package root) will be excluded from the check entirely.
final _excludedFilePatterns = <Glob>[
  Glob('lib/gen/**.dart'),
  Glob('lib/src/gen/**.dart'),
  Glob('lib/**.g.dart'),
  Glob('lib/**.freezed.dart'),
  Glob('lib/generated_plugin_registrant.dart'),
];

void main() async {
  stdout.writeln(
    '================================================================================',
  );
  stdout.writeln(
    '             Monorepo Unused File Detector                      ',
  );
  stdout.writeln(
    '================================================================================',
  );
  final stopwatch = Stopwatch()..start();

  final projectRoot = Directory.current.path;
  final projectRootPosix = p.posix.normalize(projectRoot.replaceAll(r'\', '/'));
  stdout.writeln('[INFO] Project root: $projectRootPosix');

  // 1. Scan monorepo packages
  final packages = MonorepoHelper.getPackages(projectRootPosix);
  stdout.writeln('[INFO] Found ${packages.length} packages in workspace.');

  // 2. Get all Dart files under lib/ directories
  final allDartFiles = MonorepoHelper.getAllDartFilesToScan(
    projectRootPosix,
    _excludedFilePatterns,
  );
  if (allDartFiles.isEmpty) {
    stdout.writeln('[WARNING] No Dart files found to analyze.');
    return;
  }
  stdout.writeln('[INFO] Found ${allDartFiles.length} Dart files to analyze.');

  // 3. Determine Entry Points
  final entryPoints = <String>{};
  for (final file in allDartFiles) {
    final normalized = file.replaceAll('\\', '/');

    // Check if it's the main entry point of the app
    if (normalized.endsWith('/app/lib/main.dart')) {
      entryPoints.add(file);
      continue;
    }

    // Treat any file directly under the lib/ directory (not in subdirectories like src/) as public entry point
    final parts = normalized.split('/');
    final libIndex = parts.indexOf('lib');
    if (libIndex != -1 && libIndex == parts.length - 2) {
      entryPoints.add(file);
      continue;
    }

    // DI files (often loaded dynamically/externically)
    if (normalized.contains('/lib/di/')) {
      entryPoints.add(file);
      continue;
    }

    // Routing files
    final name = p.basename(normalized).toLowerCase();
    if (name.contains('route') || name.contains('routing')) {
      entryPoints.add(file);
      continue;
    }
  }

  stdout.writeln(
    '[INFO] Identified ${entryPoints.length} entry points across all packages.',
  );

  // 4. Traverse dependency graph
  final usedFiles = findUsedFilesByGraphTraversal(
    projectRootPosix,
    allDartFiles,
    entryPoints,
  );

  stdout.writeln('[INFO] Identified ${usedFiles.length} actively used files.');

  // 5. Determine unused files
  final unusedFiles = allDartFiles.difference(usedFiles);

  stopwatch.stop();
  stdout.writeln(
    '================================================================================',
  );
  stdout.writeln(
    '             Unused File Check Results (${stopwatch.elapsed.inMilliseconds}ms)               ',
  );
  stdout.writeln(
    '================================================================================',
  );

  if (unusedFiles.isEmpty) {
    stdout.writeln('✅ Success! No unused Dart files found in workspace.');
    exit(0);
  } else {
    stdout.writeln(
      '⚠️ Found ${unusedFiles.length} potentially unused Dart files:',
    );
    final sortedUnusedFiles = unusedFiles.toList()..sort();

    final packagesWithUnused = <String, List<String>>{};
    for (final file in sortedUnusedFiles) {
      final rel = p.posix.relative(file, from: projectRootPosix);
      String pkgName = 'unknown';
      if (rel.startsWith('packages/features/')) {
        pkgName = rel.split('/')[2];
      } else if (rel.startsWith('packages/core/')) {
        pkgName = rel.split('/')[2];
      } else if (rel.startsWith('packages/data/')) {
        pkgName = rel.split('/')[2];
      } else if (rel.startsWith('packages/domain/')) {
        pkgName = rel.split('/')[2];
      } else if (rel.startsWith('app/')) {
        pkgName = 'app';
      } else if (rel.startsWith('packages/')) {
        pkgName = rel.split('/')[1];
      }
      packagesWithUnused.putIfAbsent(pkgName, () => []).add(rel);
    }

    for (final entry in packagesWithUnused.entries) {
      stdout.writeln('\n📦 Module: ${entry.key}');
      for (final file in entry.value) {
        stdout.writeln('  - $file');
      }
    }

    stdout.writeln('\nNotes:');
    stdout.writeln(
      '  - Files are considered used if reachable from main.dart, package public API barrel files, DI configuration, or routing files.',
    );
    stdout.writeln(
      '  - Files used only in unit tests might appear here as unused.',
    );
    exit(2);
  }
}

Set<String> findUsedFilesByGraphTraversal(
  String projectRootPosix,
  Set<String> allAnalyzedFiles,
  Set<String> entryPoints,
) {
  final usedFiles = <String>{};
  final worklist = Queue<String>();

  for (final ep in entryPoints) {
    if (allAnalyzedFiles.contains(ep) && usedFiles.add(ep)) {
      worklist.add(ep);
    }
  }

  while (worklist.isNotEmpty) {
    final currentFile = worklist.removeFirst();

    try {
      final content = File(currentFile).readAsStringSync();
      // Match import '...', export "...", part '...' across the entire file
      final importRegex = RegExp(
        r'''(?:import|export|part)\s+['"]([^'"]+)['"]''',
      );
      final matches = importRegex.allMatches(content);

      for (final match in matches) {
        final pathString = match.group(1);
        if (pathString == null) continue;

        final resolvedPath = MonorepoHelper.resolveDirectivePath(
          projectRootPosix,
          currentFile,
          pathString,
        );

        if (resolvedPath != null &&
            allAnalyzedFiles.contains(resolvedPath) &&
            usedFiles.add(resolvedPath)) {
          worklist.add(resolvedPath);
        }
      }
    } catch (e) {
      // Ignore reading errors silently or log them lightly
    }
  }

  return usedFiles;
}
