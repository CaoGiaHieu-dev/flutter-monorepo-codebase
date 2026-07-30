import 'dart:convert';
import 'dart:io';
import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;
import 'monorepo_helper.dart';
import 'output_formatter.dart';

void main() async {
  OutputFormatter.printHeader(
    'Monorepo Translation Key Checker',
    subtitle: 'Analyzing unused translation keys in the monorepo workspace',
  );

  final stopwatch = Stopwatch()..start();
  final projectRoot = Directory.current.path;
  final projectRootPosix = p.posix.normalize(projectRoot.replaceAll(r'\', '/'));

  // 1. Locate all packages which contain translation keys
  final packages = MonorepoHelper.getPackages(projectRootPosix);
  final packageKeys = <String, Set<String>>{};

  for (final pkg in packages.values) {
    final keys = getStringKeys(pkg.rootPath);
    if (keys.isNotEmpty) {
      packageKeys[pkg.name] = keys;
    }
  }

  if (packageKeys.isEmpty) {
    OutputFormatter.printWarning('No translation keys found to analyze.');
    exit(0);
  }

  // 3. Get all Dart files in workspace to scan for usage
  final excludedDartPatterns = [
    Glob('lib/l10n/app_localizations*.dart'),
    Glob('lib/gen/**.dart'),
    Glob('lib/src/gen/**.dart'),
    Glob('lib/**.g.dart'),
    Glob('lib/**.freezed.dart'),
  ];
  final dartFiles = MonorepoHelper.getAllDartFilesToScan(
    projectRootPosix,
    excludedDartPatterns,
  );
  OutputFormatter.printInfo(
    'Scanning ${dartFiles.length} Dart files in workspace...',
    icon: '🔍',
  );

  // 4. Find used and unused keys per package
  final unusedKeysByPackage = <String, Set<String>>{};
  int totalUnused = 0;

  for (final entry in packageKeys.entries) {
    final result = findUsedAndUnusedStringKeys(entry.value, dartFiles);
    if (result.unusedStringKeys.isNotEmpty) {
      unusedKeysByPackage[entry.key] = result.unusedStringKeys;
      totalUnused += result.unusedStringKeys.length;
    }
  }

  stopwatch.stop();
  stdout.writeln(
    '================================================================================',
  );
  stdout.writeln(
    '             Translation Key Check Results (${stopwatch.elapsed.inMilliseconds}ms)               ',
  );
  stdout.writeln(
    '================================================================================',
  );

  if (totalUnused == 0) {
    stdout.writeln('✅ Success! No unused translation keys found.');
    exit(0);
  } else {
    stdout.writeln(
      '⚠️ Found $totalUnused unused keys across ${unusedKeysByPackage.length} packages:',
    );

    for (final entry in unusedKeysByPackage.entries) {
      stdout.writeln('\n📦 Package: ${entry.key}');
      final sortedUnused = entry.value.toList()..sort();
      for (final key in sortedUnused) {
        stdout.writeln('  - $key');
      }
    }

    stdout.writeln('\nNotes:');
    stdout.writeln(
      '  - Scans for standard localization usages like context.l10n.keyName, S.of(context).keyName, etc.',
    );
    exit(2);
  }
}

Set<String> getStringKeys(String rootPath) {
  final arbDir = Directory(p.posix.join(rootPath, 'assets/language'));
  if (!arbDir.existsSync()) {
    return {};
  }

  final files = arbDir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.arb'))
      .toList();
  if (files.isEmpty) {
    stdout.writeln('Warning: No .arb files found in ${arbDir.path}.');
    return {};
  }

  // Use the first non-template arb file (or any arb file)
  final sourceFile = files.first;
  stdout.writeln(
    'Parsing translation keys from: ${p.basename(sourceFile.path)}',
  );

  final stringKeys = <String>{};
  try {
    final content = sourceFile.readAsStringSync();
    final map = jsonDecode(content) as Map<String, dynamic>;
    for (final entry in map.entries) {
      if (!entry.key.startsWith('@')) {
        stringKeys.add(entry.key);
      }
    }
  } catch (e) {
    stderr.writeln('Error reading or parsing ${sourceFile.path}: $e');
  }

  return stringKeys;
}

class StringKeyResult {
  final Set<String> usedStringKeys;
  final Set<String> unusedStringKeys;
  StringKeyResult(this.usedStringKeys, this.unusedStringKeys);
}

StringKeyResult findUsedAndUnusedStringKeys(
  Set<String> stringKeys,
  Set<String> files,
) {
  final unused = Set<String>.from(stringKeys);
  final used = <String>{};

  final keyUsageRegex = RegExp(
    r'(?:S\s*\.\s*of\(\s*context\s*\)\s*\.\s*'
    r'|AppLocalizations\s*\.\s*of\(\s*context\s*\)\s*\.\s*'
    r'|(?:\w+\s*\.\s*)*context\s*\.\s*l10n[a-zA-Z0-9_]*\s*\.\s*'
    r'|AppRouter\s*\.\s*currentContext\s*\.\s*l10n[a-zA-Z0-9_]*\s*\.\s*'
    r'|\b(?:l10n|loc)[a-zA-Z0-9_]*\s*\.\s*'
    r')'
    r'([a-zA-Z_][a-zA-Z0-9_]*)'
    r'(?![a-zA-Z0-9_])',
  );

  for (final file in files) {
    try {
      final content = File(file).readAsStringSync();

      if (!content.contains('l10n') &&
          !content.contains('loc') &&
          !content.contains('S.of(') &&
          !content.contains('AppLocalizations.of(')) {
        continue;
      }

      final matches = keyUsageRegex.allMatches(content);
      for (final match in matches) {
        final matchedKey = match.group(1);
        if (matchedKey != null && stringKeys.contains(matchedKey)) {
          used.add(matchedKey);
          unused.remove(matchedKey);
        }
      }
    } catch (e) {
      // Ignore reading errors
    }
  }

  return StringKeyResult(used, unused);
}
