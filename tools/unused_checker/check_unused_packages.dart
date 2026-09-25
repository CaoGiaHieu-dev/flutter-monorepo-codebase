import 'dart:io';

import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;

import 'monorepo_helper.dart';
import 'output_formatter.dart';

/// Whether [pkg] needs [dependency] although none of its scanned sources
/// imports it. Each case names the one condition that makes it needed —
/// there is no blanket allowlist, so a leftover declaration anywhere else is
/// reported.
bool usedWithoutImport(String dependency, MonorepoPackage pkg) {
  return switch (dependency) {
    // The SDK itself; every Flutter package declares it.
    'flutter' => true,
    // gen-l10n writes lib/src/gen/language/, which imports both — and the
    // scan skips generated files. Needed exactly when there is an l10n.yaml.
    'flutter_localizations' || 'intl' => File(
      p.join(pkg.rootPath, 'l10n.yaml'),
    ).existsSync(),
    // json_serializable refuses to build unless json_annotation is a
    // dependency, even when every source imports freezed_annotation (which
    // re-exports it).
    'json_annotation' => pkg.devDependencies.contains('json_serializable'),
    // flutter_gen's flutter_svg integration: the generated assets.gen.dart
    // imports it.
    'flutter_svg' => _flutterGenUsesSvg(pkg),
    _ => false,
  };
}

bool _flutterGenUsesSvg(MonorepoPackage pkg) {
  final flutterGen = pkg.pubspec?['flutter_gen'];
  if (flutterGen is! Map) return false;
  final integrations = flutterGen['integrations'];
  return integrations is Map && integrations['flutter_svg'] == true;
}

final _excludedSourceFilePatterns = <Glob>[
  Glob('lib/generated_plugin_registrant.dart'),
  Glob('lib/gen/**.dart'),
  Glob('lib/src/gen/**.dart'),
  Glob('lib/**.g.dart'),
  Glob('lib/**.freezed.dart'),
];

const _usage = '''
Usage: dart tools/unused_checker/check_unused_packages.dart [--help]

Reports dependencies a workspace package declares but never imports
(its lib/, bin/, test/ and tool/). Allowed without an import, each only
where it is needed: flutter; flutter_localizations and intl in a package
with an l10n.yaml; json_annotation next to json_serializable; flutter_svg
with flutter_gen's flutter_svg integration.

Works on the repository this script belongs to, whatever the working
directory. Exit 0 = clean, non-zero = findings or failure, 64 = bad argument.''';

void main(List<String> args) async {
  final projectRootPosix = MonorepoHelper.startCheck(args, usage: _usage);

  OutputFormatter.printHeader(
    'Monorepo Unused Packages Detector',
    subtitle: 'Analyzing unused dependencies across all workspace packages',
  );

  final stopwatch = Stopwatch()..start();

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
      if (!importedPackages.contains(depName) &&
          !usedWithoutImport(depName, pkg)) {
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
      '  - Dependencies are analyzed package-by-package against that package\'s own lib/, bin/, test/ and tool/ (a package with no lib/ is read whole).',
    );
    stdout.writeln(
      '  - Allowed without an import: flutter; flutter_localizations/intl with an l10n.yaml; json_annotation with json_serializable; flutter_svg with flutter_gen\'s flutter_svg integration.',
    );
    exit(2);
  }
}

Set<String> getDartFilesForPackage(String pkgRoot, String projectRoot) {
  final files = <String>{};
  final root = Directory(pkgRoot);
  if (!root.existsSync()) return files;

  // A normal package is read through lib/, bin/, test/ and tool/. A script
  // package with no lib/ — `core_tools`, whose scripts sit directly under
  // `tools/<tool>/` — is read whole; scanning only lib/ reported every one
  // of its dependencies as unused.
  const sourceRoots = {'lib', 'bin', 'test', 'tool'};
  const neverScanned = {'.dart_tool', 'build'};
  final scriptPackage = !Directory(p.join(pkgRoot, 'lib')).existsSync();

  for (final file in root.listSync(recursive: true, followLinks: false)) {
    if (file is! File || !file.path.endsWith('.dart')) continue;
    final normalized = p.posix.normalize(file.path.replaceAll('\\', '/'));
    final rel = p.posix.relative(
      normalized,
      from: p.posix.normalize(pkgRoot.replaceAll('\\', '/')),
    );
    final top = p.posix.split(rel).first;
    if (neverScanned.contains(top)) continue;
    if (!scriptPackage && !sourceRoots.contains(top)) continue;
    if (_excludedSourceFilePatterns.any((pat) => pat.matches(rel))) continue;
    files.add(normalized);
  }
  return files;
}

Set<String> findImportedPackages(Set<String> dartFiles, Set<String> declared) {
  final imported = <String>{};
  // `dotAll` matters: a directive may wrap across lines when it carries a
  // `show` / `hide` / `as` clause, e.g. the `AppFailure` re-export shim in
  // `core_common`. Without it `.*?;` stops at the first newline, the directive
  // never matches, and the package is wrongly reported as unused.
  final importRegex = RegExp(
    r'''^\s*(?:import|export)\s+['"]package:([a-zA-Z0-9_]+)(?:/[^'"]*)?['"].*?;''',
    multiLine: true,
    dotAll: true,
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
