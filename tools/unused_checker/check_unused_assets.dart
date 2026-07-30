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

void main() async {
  OutputFormatter.printHeader(
    'Monorepo Unused Assets Detector',
    subtitle: 'Analyzing unused and missing assets in the monorepo workspace',
  );

  final stopwatch = Stopwatch()..start();
  final projectRoot = Directory.current.path;
  final projectRootPosix = p.posix.normalize(projectRoot.replaceAll(r'\', '/'));
  OutputFormatter.printInfo('Project root: $projectRootPosix', icon: '📁');

  // Locate all packages in the workspace
  final packages = MonorepoHelper.getPackages(projectRootPosix);

  final allGeneratedVariableNames = <String>{};
  final allGeneratedAssetPaths = <String>{}; // Set<Absolute Path>
  final allDeclaredPaths = <String>{};
  final declaredFontPaths = <String>{};
  final declaredAssetPaths = <String>{};
  final generatedMappingsByPath =
      <String, String>{}; // absolute path -> variable name

  for (final pkg in packages.values) {
    // 1a. From assets.gen.dart
    final generatedAssetMappings = await getGeneratedAssetMappings(
      pkg.rootPath,
    );
    for (final entry in generatedAssetMappings.entries) {
      allGeneratedVariableNames.add(entry.key);
      allGeneratedAssetPaths.add(entry.value);
      generatedMappingsByPath[entry.value] = entry.key;
    }

    // 1b. From pubspec.yaml
    final declaredAssetsResult = await getAssetsFromPubspec(pkg.rootPath);
    if (declaredAssetsResult != null) {
      declaredAssetPaths.addAll(declaredAssetsResult.filePaths);
      declaredFontPaths.addAll(declaredAssetsResult.fontPaths);
      allDeclaredPaths.addAll(declaredAssetsResult.filePaths);
      allDeclaredPaths.addAll(declaredAssetsResult.fontPaths);
    }
  }

  OutputFormatter.printSuccess(
    'Found ${allGeneratedVariableNames.length} asset variables in assets.gen.dart across workspace',
    icon: '🔢',
  );
  OutputFormatter.printSuccess(
    'Found ${declaredAssetPaths.length} non-font assets and ${declaredFontPaths.length} font assets in pubspec.yaml across workspace',
    icon: '📄',
  );

  final allKnownAssetAbsolutePaths = {
    ...allGeneratedAssetPaths,
    ...allDeclaredPaths,
  };
  OutputFormatter.printInfo(
    'Total unique known asset paths: ${allKnownAssetAbsolutePaths.length}',
    icon: '📊',
  );

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

  // Get all Dart files in the workspace
  final allDartFiles = MonorepoHelper.getAllDartFilesToScan(
    projectRootPosix,
    _excludedSourceFilePatterns,
  );
  final allYamlFiles = getAllYamlFilesToScan(projectRootPosix);
  final allFilesToScanForVariables = {...allDartFiles, ...allYamlFiles};

  OutputFormatter.printInfo(
    'Scanning ${allDartFiles.length} Dart files and ${allYamlFiles.length} YAML files for Assets.variable usage',
    icon: '🔍',
  );

  // Find usage via Assets.variableName
  final usedVariableNames = findUsedAssetVariables(
    allFilesToScanForVariables,
    allGeneratedVariableNames,
  );

  final usedPathsFromVariables = <String>{};
  for (final entry in generatedMappingsByPath.entries) {
    if (usedVariableNames.contains(entry.value)) {
      usedPathsFromVariables.add(entry.key);
    }
  }

  // Find usage via literal string paths in YAML files
  final usedPathsFromYamlStrings = findUsedAssetStringPaths(
    allYamlFiles,
    allKnownAssetAbsolutePaths,
    projectRootPosix,
  );

  final allUsedAbsolutePaths = {
    ...usedPathsFromVariables,
    ...usedPathsFromYamlStrings,
  };
  OutputFormatter.printInfo(
    'Total unique used asset paths found: ${allUsedAbsolutePaths.length}',
    icon: '🔎',
  );

  // Determine Unused
  final potentiallyUnusedGeneratedPaths = allGeneratedAssetPaths.difference(
    allUsedAbsolutePaths,
  );
  final reportableUnusedGeneratedPaths = potentiallyUnusedGeneratedPaths
      .difference(declaredFontPaths);

  final finalProblemPaths = <String>{};
  finalProblemPaths.addAll(nonExistentDeclaredPaths);
  finalProblemPaths.addAll(reportableUnusedGeneratedPaths);

  // Apply Exclusions
  final reportablePathsAfterExclusions = <String>{};
  for (final assetPath in finalProblemPaths) {
    // Find which package this asset belongs to
    String? pkgRoot;
    for (final pkg in packages.values) {
      if (assetPath.startsWith(pkg.rootPath)) {
        pkgRoot = pkg.rootPath;
        break;
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
    'Generated Variables': allGeneratedVariableNames.length,
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
          '🗑️ Unused Generated Assets in ${entry.key} (${entry.value.length})',
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

Future<Map<String, String>> getGeneratedAssetMappings(String baseUiRoot) async {
  final generatedFilePath = p.posix.join(
    baseUiRoot,
    'lib/src/gen/assets.gen.dart',
  );
  final generatedFile = File(generatedFilePath);
  final mappings = <String, String>{};

  if (!generatedFile.existsSync()) {
    stdout.writeln(
      'Warning: Generated assets file not found at $generatedFilePath.',
    );
    return mappings;
  }

  try {
    final content = generatedFile.readAsStringSync();
    final regex = RegExp(
      r'''^\s*static\s+const\s+(?:[\w\.<>]+)\s+(\w+)[\s\S]*?(?:'([^']*)'|"([^"]*)")[\s\S]*?;''',
      multiLine: true,
    );
    final matches = regex.allMatches(content);

    for (final match in matches) {
      final variableName = match.group(1);
      final relativeAssetPath = match.group(2) ?? match.group(3);
      if (variableName != null && relativeAssetPath != null) {
        if (relativeAssetPath.contains('assets/')) {
          final relativeAssetPathPosix = relativeAssetPath.replaceAll(
            r'\',
            '/',
          );
          mappings[variableName] = p.posix.normalize(
            p.posix.join(baseUiRoot, relativeAssetPathPosix),
          );
        }
      }
    }
    return mappings;
  } catch (e) {
    stderr.writeln('Error reading or parsing $generatedFilePath: $e');
    return mappings;
  }
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

Set<String> findUsedAssetVariables(
  Set<String> allFilesToScan,
  Set<String> allVariableNames,
) {
  final usedVariableNames = <String>{};
  final usageRegexes = <String, RegExp>{};

  for (final variableName in allVariableNames) {
    usageRegexes[variableName] = RegExp(
      r'(?<![\w\.])Assets\s*\.\s*' + RegExp.escape(variableName) + r'(?!\w)',
    );
  }

  for (final sourceFile in allFilesToScan) {
    try {
      final fileContent = File(sourceFile).readAsStringSync();
      if (!fileContent.contains('Assets.')) continue;

      for (final variableName in allVariableNames) {
        if (usedVariableNames.contains(variableName)) continue;

        if (usageRegexes[variableName]!.hasMatch(fileContent)) {
          usedVariableNames.add(variableName);
        }
      }
    } catch (e) {
      // Ignore reading errors
    }
  }
  return usedVariableNames;
}

Set<String> findUsedAssetStringPaths(
  Set<String> allYamlFiles,
  Set<String> allKnownAssetAbsolutePaths,
  String projectRootPosix,
) {
  final usedPaths = <String>{};

  for (final yamlFile in allYamlFiles) {
    try {
      final content = File(yamlFile).readAsStringSync();
      for (final assetPath in allKnownAssetAbsolutePaths) {
        final relativePath = p.posix.relative(
          assetPath,
          from: projectRootPosix,
        );
        if (content.contains(relativePath)) {
          usedPaths.add(assetPath);
        }
      }
    } catch (e) {
      // Ignore reading errors
    }
  }
  return usedPaths;
}
