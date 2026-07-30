import 'dart:io';

Future<void> main(List<String> arguments) async {
  final bool isCheckMode = arguments.contains('--check');
  stdout.writeln(
    '================================================================',
  );
  stdout.writeln('📦 Dependency Sync & Catalog Manager for Monorepo Workspace');
  stdout.writeln(
    '================================================================',
  );

  final rootDir = Directory.current;
  final catalogFile = File('${rootDir.path}/pubspec_dependencies.yaml');

  if (!catalogFile.existsSync()) {
    stderr.writeln(
      '❌ Error: pubspec_dependencies.yaml not found at root directory!',
    );
    exit(1);
  }

  // 1. Parse Dependency Catalog
  final Map<String, String> catalog = {};
  String currentSection = '';

  for (final line in catalogFile.readAsLinesSync()) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;

    if (trimmed == 'dependencies:') {
      currentSection = 'dependencies';
      continue;
    } else if (trimmed == 'dev_dependencies:') {
      currentSection = 'dev_dependencies';
      continue;
    }

    if (trimmed.contains(':') && currentSection.isNotEmpty) {
      final parts = trimmed.split(':');
      final name = parts[0].trim();
      var version = parts.sublist(1).join(':').trim();
      if ((version.startsWith('"') && version.endsWith('"')) ||
          (version.startsWith("'") && version.endsWith("'"))) {
        version = version.substring(1, version.length - 1);
      }
      catalog[name] = version;
    }
  }

  stdout.writeln(
    '📌 Catalog loaded: ${catalog.length} shared dependencies registered.',
  );

  // 2. Discover pubspec.yaml files from root workspace settings
  final rootPubspec = File('${rootDir.path}/pubspec.yaml');
  if (!rootPubspec.existsSync()) {
    stderr.writeln('❌ Error: Root pubspec.yaml not found!');
    exit(1);
  }

  final List<String> packagePaths = [];
  bool inWorkspaceSection = false;

  for (final line in rootPubspec.readAsLinesSync()) {
    final trimmed = line.trim();
    if (trimmed == 'workspace:') {
      inWorkspaceSection = true;
      continue;
    }
    if (inWorkspaceSection) {
      if (trimmed.startsWith('-')) {
        final path = trimmed.substring(1).trim();
        packagePaths.add(path);
      } else if (trimmed.isNotEmpty &&
          !trimmed.startsWith('#') &&
          !line.startsWith(' ')) {
        inWorkspaceSection = false;
      }
    }
  }

  packagePaths.add('.');

  final Map<String, String> workspacePackageDirs = {};
  for (final pkgPath in packagePaths) {
    final pubspecFile = File('${rootDir.path}/$pkgPath/pubspec.yaml');
    if (!pubspecFile.existsSync()) continue;

    final packageName = _readPackageName(pubspecFile);
    if (packageName != null) {
      workspacePackageDirs[packageName] = pkgPath;
    }
  }

  stdout.writeln(
    '📂 Discovered ${packagePaths.length} workspace packages/directories.',
  );
  stdout.writeln(
    '🏷️  Workspace packages indexed: ${workspacePackageDirs.length}.',
  );

  int totalSynced = 0;
  int totalMismatches = 0;
  int totalRepairedPaths = 0;

  for (final pkgPath in packagePaths) {
    final pubspecFile = File('${rootDir.path}/$pkgPath/pubspec.yaml');
    if (!pubspecFile.existsSync()) continue;

    final String relativePath = pkgPath == '.'
        ? 'Root (pubspec.yaml)'
        : '$pkgPath/pubspec.yaml';
    final lines = pubspecFile.readAsLinesSync();
    final List<String> newLines = [];
    bool fileModified = false;
    String activeSection = '';
    String? pendingBlockDepName;
    const int dependencyIndent = 2;

    for (final line in lines) {
      final trimmed = line.trim();
      final indent = line.length - line.trimLeft().length;

      if (trimmed == 'dependencies:') {
        activeSection = 'dependencies';
        pendingBlockDepName = null;
        newLines.add(line);
        continue;
      } else if (trimmed == 'dev_dependencies:') {
        activeSection = 'dev_dependencies';
        pendingBlockDepName = null;
        newLines.add(line);
        continue;
      } else if (trimmed.isNotEmpty &&
          indent == 0 &&
          !trimmed.startsWith('#')) {
        activeSection = '';
        pendingBlockDepName = null;
      }

      if (activeSection.isNotEmpty && trimmed.contains(':') && indent > 0) {
        final parts = trimmed.split(':');
        final depName = parts[0].trim();
        final currentVersion = parts.sublist(1).join(':').trim();

        // Block-style dependency parent (e.g. `core_common:` + nested `path:`)
        // Empty version on a workspace package — wait for nested `path:`.
        if (indent == dependencyIndent && currentVersion.isEmpty) {
          if (workspacePackageDirs.containsKey(depName)) {
            pendingBlockDepName = depName;
            newLines.add(line);
            continue;
          }

          // Empty catalog dep (e.g. `dynamic_logger:`) — fill from pubspec_dependencies.yaml.
          if (catalog.containsKey(depName)) {
            final targetVersion = catalog[depName]!;
            totalMismatches++;
            if (isCheckMode) {
              stderr.writeln(
                '⚠️  Missing version: [$relativePath] $depName (expected "$targetVersion")',
              );
              newLines.add(line);
            } else {
              stdout.writeln(
                '⚡ Syncing missing: [$relativePath] -> $depName: "$targetVersion"',
              );
              final leadingIndent = ' ' * indent;
              newLines.add('$leadingIndent$depName: "$targetVersion"');
              fileModified = true;
            }
            continue;
          }

          pendingBlockDepName = depName;
          newLines.add(line);
          continue;
        }

        // Nested dependency source keys (e.g. `path: ../common` under `core_common:`)
        if (indent > dependencyIndent) {
          if (depName == 'path' &&
              pendingBlockDepName != null &&
              workspacePackageDirs.containsKey(pendingBlockDepName)) {
            final targetDir = workspacePackageDirs[pendingBlockDepName]!;
            final expectedPath = _relativePathBetween(pkgPath, targetDir);
            final cleanedPath = _stripQuotes(currentVersion);

            if (_looksLikePubVersion(cleanedPath) ||
                cleanedPath != expectedPath) {
              if (isCheckMode) {
                totalMismatches++;
                stderr.writeln(
                  '⚠️  Broken local path: [$relativePath] $pendingBlockDepName -> path: "$cleanedPath" (expected "$expectedPath")',
                );
                newLines.add(line);
              } else {
                stdout.writeln(
                  '🔧 Repairing local path: [$relativePath] $pendingBlockDepName -> path: "$expectedPath"',
                );
                final leadingIndent = ' ' * indent;
                newLines.add('$leadingIndent$depName: $expectedPath');
                fileModified = true;
                totalRepairedPaths++;
              }
              continue;
            }
          }

          newLines.add(line);
          continue;
        }

        if (indent == dependencyIndent) {
          pendingBlockDepName = null;
        }

        // Inline dependency version sync from catalog
        if (indent == dependencyIndent &&
            catalog.containsKey(depName) &&
            !currentVersion.contains('path:') &&
            !currentVersion.contains('sdk:') &&
            !workspacePackageDirs.containsKey(depName)) {
          final targetVersion = catalog[depName]!;
          final cleanedCurrentVersion = _stripQuotes(currentVersion);

          if (cleanedCurrentVersion != targetVersion) {
            totalMismatches++;
            if (isCheckMode) {
              stderr.writeln(
                '⚠️  Mismatch: [$relativePath] uses $depName: "$cleanedCurrentVersion" instead of "$targetVersion"',
              );
              newLines.add(line);
            } else {
              stdout.writeln(
                '⚡ Syncing: [$relativePath] -> $depName from "$cleanedCurrentVersion" to "$targetVersion"',
              );
              final leadingIndent = ' ' * indent;
              newLines.add('$leadingIndent$depName: "$targetVersion"');
              fileModified = true;
            }
            continue;
          }
        }
      } else if (indent <= dependencyIndent) {
        pendingBlockDepName = null;
      }

      newLines.add(line);
    }

    if (fileModified && !isCheckMode) {
      pubspecFile.writeAsStringSync('${newLines.join('\n')}\n');
      totalSynced++;
    }
  }

  stdout.writeln(
    '================================================================',
  );
  if (isCheckMode) {
    if (totalMismatches > 0) {
      stderr.writeln(
        '❌ Mismatch detected! $totalMismatches dependency discrepancies found in the workspace.',
      );
      stderr.writeln(
        '💡 Run `dart tools/dependency_sync.dart` to automatically resolve all discrepancies.',
      );
      exit(1);
    } else {
      stdout.writeln(
        '✅ Success: All packages in the workspace are in perfect sync with the catalog!',
      );
    }
  } else {
    if (totalSynced > 0) {
      stdout.writeln(
        '🚀 Successfully updated and synchronized $totalSynced packages with the dependency catalog.',
      );
      if (totalRepairedPaths > 0) {
        stdout.writeln(
          '🔧 Repaired $totalRepairedPaths broken local package paths.',
        );
      }
    } else {
      stdout.writeln(
        '✅ All packages in the workspace are already in perfect synchronization!',
      );
    }
  }

  stdout.writeln(
    '💡 Running `flutter pub get` to apply the updates...',
  );

  /// If fvm is setup then run with fvm
  final executable = Platform.resolvedExecutable;
  final getArgs = ['pub', 'get'];
  // 3. Chạy pub get (ẩn log trừ khi lỗi)
  final getResult = await Process.run(
    executable,
    getArgs,
  );

  if (getResult.exitCode != 0) {
    stderr.writeln('❌ Failed to resolve dependencies in sandbox!');
    stderr.writeln(getResult.stderr);
    exit(1);
  }

  stdout.writeln(
    '================================================================',
  );
}

String? _readPackageName(File pubspecFile) {
  for (final line in pubspecFile.readAsLinesSync()) {
    final trimmed = line.trim();
    if (trimmed.startsWith('name:')) {
      return trimmed.substring('name:'.length).trim();
    }
    if (trimmed.isNotEmpty &&
        !trimmed.startsWith('#') &&
        !line.startsWith(' ')) {
      break;
    }
  }
  return null;
}

String _stripQuotes(String value) {
  if ((value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))) {
    return value.substring(1, value.length - 1);
  }
  return value;
}

bool _looksLikePubVersion(String value) {
  return RegExp(r'^[\^~<>=]*\d').hasMatch(value);
}

String _relativePathBetween(String fromDir, String toDir) {
  final fromParts = _normalizePath(fromDir).split('/');
  final toParts = _normalizePath(toDir).split('/');

  var commonPrefixLength = 0;
  while (commonPrefixLength < fromParts.length &&
      commonPrefixLength < toParts.length &&
      fromParts[commonPrefixLength] == toParts[commonPrefixLength]) {
    commonPrefixLength++;
  }

  final upLevels = List<String>.filled(
    fromParts.length - commonPrefixLength,
    '..',
  );
  final downLevels = toParts.sublist(commonPrefixLength);

  if (upLevels.isEmpty && downLevels.isEmpty) {
    return '.';
  }

  return [...upLevels, ...downLevels].join('/');
}

String _normalizePath(String path) {
  return path.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), '');
}
