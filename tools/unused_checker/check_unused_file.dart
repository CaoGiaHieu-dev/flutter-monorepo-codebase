import 'dart:collection';
import 'dart:io';

import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;

import 'monorepo_helper.dart';

/// A class-level injectable annotation at the start of a line.
final _injectableAnnotation = RegExp(
  r'^@(?:module|injectable|singleton|lazySingleton|Injectable|Singleton|LazySingleton)\b',
  multiLine: true,
);

// --- Configuration ---
// Files matching these patterns (relative to package root) will be excluded from the check entirely.
final _excludedFilePatterns = <Glob>[
  Glob('lib/gen/**.dart'),
  Glob('lib/src/gen/**.dart'),
  Glob('lib/**.g.dart'),
  Glob('lib/**.freezed.dart'),
  Glob('lib/generated_plugin_registrant.dart'),
];

const _usage = '''
Usage: dart tools/unused_checker/check_unused_file.dart [--help]

Reports Dart files under a package's lib/ that no used code reaches.

Entry points: every lib/main.dart, every file under lib/di/, routing files
(name contains "route"/"routing"), injectable-annotated classes, and any
file directly under lib/ other than the package barrel. From there a file
is reached by a relative or package import/export/part — except through a
package barrel (lib/<package>.dart): a file the barrel exports counts as
used only when a file importing that barrel names one of its public
declarations. A barrel export alone is not a use, so a file nothing
references is reported even though its package exports it. Files that
declare only extensions or re-exports are counted as used once their
barrel is imported (their use cannot be seen by name).

Works on the repository this script belongs to, whatever the working
directory. Exit 0 = clean, non-zero = findings or failure, 64 = bad argument.''';

void main(List<String> args) async {
  final projectRootPosix = MonorepoHelper.startCheck(args, usage: _usage);

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
  final entryPoints = <String>{
    for (final file in allDartFiles)
      if (isEntryPoint(file, packages.values)) file,
  };

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

  // 5. Determine unused files. A barrel is the package's public surface,
  // not a file anything "uses": it is never reported.
  final barrels = barrelFiles(packages.values);
  final unusedFiles = allDartFiles
      .difference(usedFiles)
      .difference(barrels);

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
      // Resolved against the discovered package list rather than by matching
      // a path prefix: prefixes hardcode a layout, and a package that moves
      // then reports as `unknown` instead of by name.
      var pkgName = 'unknown';
      var bestLen = -1;
      for (final pkg in MonorepoHelper.getPackages(projectRootPosix).values) {
        final pkgRel = p.posix.relative(pkg.rootPath, from: projectRootPosix);
        if ((rel == pkgRel || rel.startsWith('$pkgRel/')) &&
            pkgRel.length > bestLen) {
          pkgName = pkg.name;
          bestLen = pkgRel.length;
        }
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
      '  - Files are used when reachable from main.dart, lib/di/, routing files or injectable classes; a package barrel export counts only when an importer names the file\'s declarations.',
    );
    stdout.writeln(
      '  - Files used only in unit tests might appear here as unused.',
    );
    exit(2);
  }
}

/// Whether [file] is where reachability starts: an app's `lib/main.dart`,
/// DI configuration (`lib/di/`, loaded by the generator), a routing file, a
/// class injectable registers by annotation, or a public library other than
/// its package's barrel (a file directly under `lib/`).
bool isEntryPoint(String file, Iterable<MonorepoPackage> packages) {
  final normalized = file.replaceAll('\\', '/');
  if (normalized.endsWith('/lib/main.dart')) return true;

  final parts = normalized.split('/');
  final libIndex = parts.lastIndexOf('lib');
  if (libIndex != -1 && libIndex == parts.length - 2) {
    return !barrelFiles(packages).contains(normalized);
  }

  if (normalized.contains('/lib/di/')) return true;

  final name = p.basename(normalized).toLowerCase();
  if (name.contains('route') || name.contains('routing')) return true;

  // Injectable registrations. The generator finds these by annotation, not
  // by import, so nothing hand-written need reference them — an app's
  // `lib/firebase/firebase_module.dart` is reachable from no import at all.
  try {
    return _injectableAnnotation.hasMatch(File(file).readAsStringSync());
  } on FileSystemException {
    // Unreadable: leave it to the reachability pass to report.
    return false;
  }
}

/// Every package's barrel, `lib/<package name>.dart`.
Set<String> barrelFiles(Iterable<MonorepoPackage> packages) => {
  for (final pkg in packages)
    p.posix.normalize(p.posix.join(pkg.rootPath, 'lib', '${pkg.name}.dart')),
};

final _directive = RegExp(
  r'''^\s*(import|export|part)\s+['"]([^'"]+)['"]''',
  multiLine: true,
);

final _identifier = RegExp(r'[A-Za-z_$][A-Za-z0-9_$]*');

/// Public top-level names a file declares — what an importer of its barrel
/// would have to write to use it. `null` when the file declares an
/// extension (used by member name, invisible to this scan) or nothing
/// public at all (a re-export shim): its use cannot be seen by name.
Set<String>? declaredNames(String content) {
  if (RegExp(r'^extension\b', multiLine: true).hasMatch(content)) return null;
  final names = <String>{
    for (final m in RegExp(
      r'^(?:(?:abstract|sealed|base|final|interface|mixin)\s+)*'
      r'(?:class|mixin|enum|typedef|extension\s+type)\s+([A-Za-z]\w*)',
      multiLine: true,
    ).allMatches(content))
      m.group(1)!,
    // Top-level functions, getters and variables: an unindented line that is
    // not a directive or a type declaration, ending its name with `(`, `=`,
    // `;` or `=>`.
    for (final m in RegExp(
      r'^(?!(?:import|export|part|library|class|abstract|sealed|base|final class|interface|mixin|enum|typedef|extension)\b)'
      r'(?:(?:final|const|var|late|external)\s+)*(?:[\w<>?,.\[\]]+\s+)*?(?:get\s+)?([A-Za-z]\w*)\s*(?:<[^>(]*>)?\s*(?:\(|=>|=|;)',
      multiLine: true,
    ).allMatches(content))
      m.group(1)!,
  };
  return names.isEmpty ? null : names;
}

Set<String> findUsedFilesByGraphTraversal(
  String projectRootPosix,
  Set<String> allAnalyzedFiles,
  Set<String> entryPoints,
) {
  final packages = MonorepoHelper.getPackages(projectRootPosix).values;
  final barrels = barrelFiles(packages);
  final contents = <String, String>{};
  String read(String file) => contents.putIfAbsent(file, () {
    try {
      return File(file).readAsStringSync();
    } on FileSystemException {
      return '';
    }
  });

  Iterable<(String, String)> directives(String file) sync* {
    for (final m in _directive.allMatches(read(file))) {
      final target = MonorepoHelper.resolveDirectivePath(
        projectRootPosix,
        file,
        m.group(2)!,
      );
      if (target != null) yield (m.group(1)!, target);
    }
  }

  // Every file a barrel exposes: its exports, and theirs, across packages.
  final exposedCache = <String, Set<String>>{};
  Set<String> exposedBy(String barrel) =>
      exposedCache.putIfAbsent(barrel, () {
        final out = <String>{};
        final queue = Queue<String>()..add(barrel);
        while (queue.isNotEmpty) {
          for (final (kind, target) in directives(queue.removeFirst())) {
            if (kind == 'export' && out.add(target)) queue.add(target);
          }
        }
        return out;
      });

  final namesCache = <String, Set<String>?>{};
  Set<String>? namesOf(String file) =>
      namesCache.putIfAbsent(file, () => declaredNames(read(file)));

  final usedFiles = <String>{};
  final worklist = Queue<String>();
  void use(String file) {
    if (allAnalyzedFiles.contains(file) && usedFiles.add(file)) {
      worklist.add(file);
    }
  }

  entryPoints.forEach(use);

  while (worklist.isNotEmpty) {
    final current = worklist.removeFirst();
    Set<String>? identifiers;
    for (final (kind, target) in directives(current)) {
      if (!barrels.contains(target)) {
        use(target);
        continue;
      }
      // Re-exporting a whole barrel makes all of it part of this file's
      // surface; nothing finer can be told.
      if (kind == 'export') {
        exposedBy(target).forEach(use);
        continue;
      }
      // Importing a barrel uses exactly the exposed files whose names this
      // file mentions.
      identifiers ??= {
        for (final m in _identifier.allMatches(read(current))) m.group(0)!,
      };
      for (final exposed in exposedBy(target)) {
        final names = namesOf(exposed);
        if (names == null || names.any(identifiers.contains)) use(exposed);
      }
    }
  }

  return usedFiles;
}
