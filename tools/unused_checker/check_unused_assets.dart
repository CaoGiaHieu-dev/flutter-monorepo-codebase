import 'dart:io';

import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'monorepo_helper.dart';
import 'output_formatter.dart';

// --- Configuration ---
final _excludedSourceFilePatterns = <Glob>[
  Glob('lib/gen/**.dart'),
  Glob('lib/src/gen/**.dart'),
  Glob('lib/**.g.dart'),
  Glob('lib/**.freezed.dart'),
];

final _excludedScanFiles = <String>{
  'pubspec.yaml',
  'pubspec.lock',
  'analysis_options.yaml',
  'l10n.yaml',
  'build.yaml',
};

final _excludedAssetPatterns = <Glob>[
  Glob('assets/icons/flag/**.svg'),
  Glob('assets/json/country.json'),
];

const _usage = '''
Usage: dart tools/unused_checker/check_unused_assets.dart [--help]

Reports assets declared or shipped by a workspace package that no Dart
file references, and asset references that point at nothing.

Works on the repository this script belongs to, whatever the working
directory. Exit 0 = clean, non-zero = findings or failure, 64 = bad argument.''';

void main(List<String> args) async {
  final projectRootPosix = MonorepoHelper.startCheck(args, usage: _usage);

  OutputFormatter.printHeader(
    'Monorepo Unused Assets Detector',
    subtitle: 'Analyzing unused and missing assets in the monorepo workspace',
  );

  final stopwatch = Stopwatch()..start();
  OutputFormatter.printInfo('Project root: $projectRootPosix', icon: '📁');

  // Locate all packages in the workspace
  final packages = MonorepoHelper.getPackages(projectRootPosix);

  final allDeclaredPaths = <String>{};
  final declaredFontPaths = <String>{};
  final declaredAssetPaths = <String>{};
  // Absolute asset path -> how code can reach it: the flutter_gen accessor
  // (`Assets.icons.logo`) and the package-relative path (`assets/icons/logo.svg`).
  final accessorByPath = <String, String>{};
  final relativeByPath = <String, String>{};

  for (final pkg in packages.values) {
    final declaredAssetsResult = await getAssetsFromPubspec(pkg.rootPath);
    if (declaredAssetsResult == null) continue;
    declaredAssetPaths.addAll(declaredAssetsResult.filePaths);
    declaredFontPaths.addAll(declaredAssetsResult.fontPaths);
    allDeclaredPaths.addAll(declaredAssetsResult.filePaths);
    allDeclaredPaths.addAll(declaredAssetsResult.fontPaths);
    for (final asset in declaredAssetsResult.filePaths) {
      final rel = p.posix.relative(asset, from: pkg.rootPath);
      relativeByPath[asset] = rel;
      final accessor = flutterGenAccessor(rel);
      if (accessor != null) accessorByPath[asset] = accessor;
    }
  }

  OutputFormatter.printSuccess(
    'Found ${declaredAssetPaths.length} non-font assets and ${declaredFontPaths.length} font assets in pubspec.yaml across workspace',
    icon: '📄',
  );

  final allKnownAssetAbsolutePaths = {...allDeclaredPaths};

  // 2. Check Asset Existence
  OutputFormatter.printSection('Checking File Existence', icon: '🔍');
  final nonExistentDeclaredPaths = <String>{};
  for (final declaredPath in allDeclaredPaths) {
    if (!FileSystemEntity.isFileSync(declaredPath)) {
      nonExistentDeclaredPaths.add(declaredPath);
    }
  }
  if (nonExistentDeclaredPaths.isNotEmpty) {
    OutputFormatter.printWarning(
      'Found ${nonExistentDeclaredPaths.length} declared assets that do not exist on filesystem',
      icon: '🚫',
    );
  } else {
    OutputFormatter.printSuccess(
      'All declared assets exist on filesystem',
      icon: '✅',
    );
  }

  // 3. Scan for Asset Usage across entire workspace
  OutputFormatter.printSection('Scanning for Asset Usage', icon: '🔎');

  final allDartFiles = MonorepoHelper.getAllDartFilesToScan(
    projectRootPosix,
    _excludedSourceFilePatterns,
  );
  final allYamlFiles = getAllYamlFilesToScan(projectRootPosix);
  final sources = <String>[];
  for (final file in {...allDartFiles, ...allYamlFiles}) {
    try {
      sources.add(File(file).readAsStringSync());
    } catch (_) {
      // Unreadable file: nothing to find in it.
    }
  }

  OutputFormatter.printInfo(
    'Scanning ${allDartFiles.length} Dart files and ${allYamlFiles.length} YAML files',
    icon: '🔍',
  );

  // An asset is used when some source names its flutter_gen accessor or its
  // path. Nested accessors are matched as a whole chain, so `Assets.icons`
  // alone does not mark every icon used.
  final allUsedAbsolutePaths = <String>{};
  for (final asset in declaredAssetPaths) {
    final accessor = accessorByPath[asset];
    final accessorRegex = accessor == null
        ? null
        : RegExp('${RegExp.escape(accessor)}(?![\\w])');
    final rel = relativeByPath[asset]!;
    for (final content in sources) {
      if (content.contains(rel) ||
          (accessorRegex != null && accessorRegex.hasMatch(content))) {
        allUsedAbsolutePaths.add(asset);
        break;
      }
    }
  }
  OutputFormatter.printInfo(
    'Total unique used asset paths found: ${allUsedAbsolutePaths.length}',
    icon: '🔎',
  );

  // Determine Unused (fonts are referenced by family name, not path)
  final reportableUnusedPaths = declaredAssetPaths
      .difference(allUsedAbsolutePaths)
      .difference(declaredFontPaths)
      .difference(nonExistentDeclaredPaths);

  final finalProblemPaths = <String>{};
  finalProblemPaths.addAll(nonExistentDeclaredPaths);
  finalProblemPaths.addAll(reportableUnusedPaths);

  // Apply Exclusions
  final reportablePathsAfterExclusions = <String>{};
  for (final assetPath in finalProblemPaths) {
    // Find which package this asset belongs to
    // Longest matching root: a package nested inside another must win.
    String? pkgRoot;
    for (final pkg in packages.values) {
      if (assetPath.startsWith('${pkg.rootPath}/') &&
          (pkgRoot == null || pkg.rootPath.length > pkgRoot.length)) {
        pkgRoot = pkg.rootPath;
      }
    }
    pkgRoot ??= projectRootPosix;

    final relativePath = p.posix.relative(assetPath, from: pkgRoot);
    bool isExcluded = _excludedAssetPatterns.any(
      (pattern) => pattern.matches(relativePath),
    );
    if (!isExcluded) {
      reportablePathsAfterExclusions.add(assetPath);
    }
  }

  stopwatch.stop();
  OutputFormatter.printTiming('Asset analysis', stopwatch.elapsed);

  final stats = {
    'Total Known Assets': allKnownAssetAbsolutePaths.length,
    'Declared Assets': allDeclaredPaths.length,
    'Missing Files': nonExistentDeclaredPaths.length,
    'Issues Found': reportablePathsAfterExclusions.length,
  };

  if (reportablePathsAfterExclusions.isEmpty) {
    OutputFormatter.printFinalResult(
      success: true,
      message: 'No unused assets or missing files found!',
      stats: stats,
    );
    exit(0);
  } else {
    OutputFormatter.printFinalResult(
      success: false,
      message:
          'Found ${reportablePathsAfterExclusions.length} potential asset issues',
      stats: stats,
    );

    OutputFormatter.printSection('Asset Issues Found', icon: '⚠️');

    final missingByPackage = <String, List<String>>{};
    final unusedByPackage = <String, List<String>>{};

    for (final assetPath in reportablePathsAfterExclusions) {
      final rel = p.posix.relative(assetPath, from: projectRootPosix);
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

      if (nonExistentDeclaredPaths.contains(assetPath)) {
        missingByPackage.putIfAbsent(pkgName, () => []).add(rel);
      } else {
        unusedByPackage.putIfAbsent(pkgName, () => []).add(rel);
      }
    }

    if (missingByPackage.isNotEmpty) {
      for (final entry in missingByPackage.entries) {
        OutputFormatter.printBox(
          '🚫 Missing Files in ${entry.key} (${entry.value.length})',
          entry.value.map((path) => '📄 $path').toList(),
          color: 'red',
        );
      }
    }

    if (unusedByPackage.isNotEmpty) {
      for (final entry in unusedByPackage.entries) {
        OutputFormatter.printBox(
          '🗑️ Unused Assets in ${entry.key} (${entry.value.length})',
          entry.value.map((path) => '🖼️ $path').toList(),
          color: 'yellow',
        );
      }
    }

    // If there are missing files, exit 1. If only unused assets, exit 2 (warning).
    if (missingByPackage.isNotEmpty) {
      exit(1);
    } else {
      exit(2);
    }
  }
}

class PubspecAssetsResult {
  final Set<String> filePaths;
  final Set<String> fontPaths;
  PubspecAssetsResult(this.filePaths, this.fontPaths);
}

Future<PubspecAssetsResult?> getAssetsFromPubspec(String baseUiRoot) async {
  final pubspecPath = p.posix.join(baseUiRoot, 'pubspec.yaml');
  final pubspecFile = File(pubspecPath);
  final declaredAssetFiles = <String>{};
  final declaredFontFiles = <String>{};

  if (!pubspecFile.existsSync()) {
    stderr.writeln('Error: pubspec.yaml not found at $pubspecPath');
    return null;
  }

  try {
    final content = pubspecFile.readAsStringSync();
    final yamlMap = loadYaml(content) as YamlMap?;
    final flutterMap = yamlMap?['flutter'] as YamlMap?;

    final assetsList = flutterMap?['assets'] as YamlList?;
    if (assetsList != null) {
      for (final entry in assetsList) {
        if (entry is String) {
          final relativeAssetPath = entry.replaceAll(r'\', '/');
          if (relativeAssetPath.endsWith('/')) {
            final directoryGlob = Glob('$relativeAssetPath*');
            try {
              for (var entity in directoryGlob.listSync(
                root: baseUiRoot,
                followLinks: false,
              )) {
                if (entity is File) {
                  declaredAssetFiles.add(
                    p.posix.normalize(entity.path.replaceAll(r'\', '/')),
                  );
                }
              }
            } catch (e) {
              // Ignore listing errors silently
            }
          } else {
            declaredAssetFiles.add(
              p.posix.normalize(p.posix.join(baseUiRoot, relativeAssetPath)),
            );
          }
        }
      }
    }

    final fontsList = flutterMap?['fonts'] as YamlList?;
    if (fontsList != null) {
      for (final fontEntry in fontsList) {
        if (fontEntry is YamlMap) {
          final fontAssetsList = fontEntry['fonts'] as YamlList?;
          if (fontAssetsList != null) {
            for (final asset in fontAssetsList) {
              String? relativeFontPath;
              if (asset is String) {
                relativeFontPath = asset;
              } else if (asset is YamlMap && asset['asset'] is String) {
                relativeFontPath = asset['asset'] as String;
              }

              if (relativeFontPath != null) {
                final relativeFontPathPosix = relativeFontPath.replaceAll(
                  r'\',
                  '/',
                );
                declaredFontFiles.add(
                  p.posix.normalize(
                    p.posix.join(baseUiRoot, relativeFontPathPosix),
                  ),
                );
              }
            }
          }
        }
      }
    }
    return PubspecAssetsResult(declaredAssetFiles, declaredFontFiles);
  } catch (e) {
    stderr.writeln('Error parsing pubspec.yaml at $pubspecPath: $e');
    return null;
  }
}

/// The accessor flutter_gen generates for [relativePath] with its default
/// nested style: `assets/icons/logo.svg` -> `Assets.icons.logo`. `null` for a
/// path outside `assets/`, which flutter_gen does not expose that way.
String? flutterGenAccessor(String relativePath) {
  final segments = relativePath.split('/');
  if (segments.length < 2 || segments.first != 'assets') return null;
  final dirs = segments.sublist(1, segments.length - 1);
  final file = p.posix.basenameWithoutExtension(segments.last);
  return ['Assets', ...dirs.map(_camelCase), _camelCase(file)].join('.');
}

String _camelCase(String value) {
  final words = value
      .split(RegExp(r'[_\-\s.]+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return value;
  return words.first.toLowerCase() +
      words.skip(1).map((w) => w[0].toUpperCase() + w.substring(1)).join();
}

Set<String> getAllYamlFilesToScan(String projectRootPosix) {
  final yamlGlob = Glob('**.yaml');
  final yamlFiles = <String>{};

  try {
    for (var entity in yamlGlob.listSync(
      root: projectRootPosix,
      followLinks: false,
    )) {
      if (entity is File) {
        final filePath = p.posix.normalize(entity.path.replaceAll(r'\', '/'));
        final base = p.basename(filePath);
        if (!_excludedScanFiles.contains(base)) {
          yamlFiles.add(filePath);
        }
      }
    }
  } catch (e) {
    // Ignore listing errors
  }
  return yamlFiles;
}
