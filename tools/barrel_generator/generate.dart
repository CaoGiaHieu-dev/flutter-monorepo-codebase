import 'dart:io';

import 'package:path/path.dart' as p;

import '../shared/toolchain.dart';

const _usage = '''
Usage: dart tools/barrel_generator/generate.dart [<package>/lib]

Regenerates the `export` barrel of every directory under the given path
(default: lib), then runs `dart format` on it.

  dart tools/barrel_generator/generate.dart modules/<module>/<layer>/lib

Hand-written `export` lines in a barrel are replaced. Run it after
gen-l10n / build_runner: generated files on disk are exported too.
Exits 64 when the path does not exist or on a flag, 1 when generation or
formatting fails.''';

/// Directories never given a barrel, matched as whole path SEGMENTS relative
/// to the package root (the nearest ancestor of the target holding a
/// `pubspec.yaml`) — never as substrings, and never inside `lib/`.
///
/// They used to be matched as substrings of the whole path, anywhere. That was
/// meant for runs over a package root, but it also dropped legitimate source:
/// `lib/src/widgets/web/web_view.dart` was never exported because `web`
/// appeared in its path. Inside `lib/` only `lib/gen` (flutter_gen output,
/// exported by nothing) and hidden directories are skipped; `lib/src/gen`,
/// whose barrel `core_base_ui` exports, is walked as before.
const _excludedOutsideLib = {
  'build',
  'ios',
  'android',
  'macos',
  'windows',
  'linux',
  'web',
};

// Cross-platform path helpers
String _join(String part1, String part2) {
  if (part1.isEmpty) return part2;
  if (part2.isEmpty) return part1;
  final endsWithSlash = part1.endsWith('/') || part1.endsWith('\\');
  final startsWithSlash = part2.startsWith('/') || part2.startsWith('\\');
  if (endsWithSlash && startsWithSlash) {
    return part1 + part2.substring(1);
  } else if (!endsWithSlash && !startsWithSlash) {
    return '$part1/$part2';
  } else {
    return part1 + part2;
  }
}

String _basename(String path) {
  final parts = path
      .replaceAll('\\', '/')
      .split('/')
      .where((s) => s.isNotEmpty)
      .toList();
  return parts.isEmpty ? '' : parts.last;
}

/// `lib/` and `lib` name the same directory. Left in, the trailing separator
/// made the package directory's basename empty and the barrel came out as
/// `lib/.dart`.
String _stripTrailingSeparators(String path) {
  var out = path;
  while (out.length > 1 && (out.endsWith('/') || out.endsWith('\\'))) {
    out = out.substring(0, out.length - 1);
  }
  return out;
}

void main(List<String> args) {
  if (args.contains('--help') || args.contains('-h')) {
    stdout.writeln(_usage);
    return;
  }
  // A flag is never a path: `--help` used to be taken for a directory name.
  final flag = args.where((a) => a.startsWith('-')).firstOrNull;
  if (flag != null || args.length > 1) {
    stderr.writeln(
      flag != null
          ? '[ERROR] Unknown flag: $flag'
          : '[ERROR] Expected one path, got: ${args.join(' ')}',
    );
    stderr.writeln(_usage);
    exit(64);
  }

  var targetDir = 'lib';
  if (args.isNotEmpty) {
    targetDir = _stripTrailingSeparators(args[0]);
  }

  var dir = Directory(targetDir);
  // Ask for another path only when a person is there to answer. An agent or
  // a CI step passing a wrong path used to block forever on stdin.
  if (!dir.existsSync() && (args.isNotEmpty || !stdin.hasTerminal)) {
    stderr.writeln('[ERROR] Directory "$targetDir" does not exist.');
    exit(64);
  }
  while (!dir.existsSync()) {
    stderr.writeln('[ERROR] Directory "$targetDir" does not exist.');
    stdout.write(
      'Enter a valid directory path (or "exit" to quit): ',
    );
    final input = stdin.readLineSync();
    if (input == null || input.trim().toLowerCase() == 'exit') {
      exit(1);
    }
    targetDir = _stripTrailingSeparators(input.trim());
    dir = Directory(targetDir);
  }

  stdout.writeln(
    '\n[INFO] Creating/updating barrel files for "$targetDir"...',
  );
  stdout.writeln(
    '[INFO] Rules: exports sorted, placed after imports; hand-written code kept.',
  );

  try {
    final allDirs = _getAllDirectories(dir);
    for (final subDir in allDirs) {
      _createOrUpdateBarrelForDir(subDir);
    }

    stdout.writeln('\n[INFO] Formatting "$targetDir"...');
    // Through the repo's toolchain (`fvm dart` when FVM is set up), not the
    // SDK that happens to run this script.
    final result = Process.runSync(dartExecutable, [
      ...dartArgs,
      'format',
      targetDir,
    ], runInShell: true);
    stdout.write(result.stdout);
    if (result.exitCode != 0) {
      stderr.write(result.stderr);
      stderr.writeln(
        '[ERROR] dart format failed (exit ${result.exitCode}). The barrels '
        'were written but not formatted.',
      );
      exit(1);
    }

    stdout.writeln('\n[SUCCESS] Barrel files generated.');
  } catch (e) {
    stderr.writeln('[ERROR] Unexpected error: $e');
    exit(1);
  }
}

List<Directory> _getAllDirectories(Directory root) {
  final result = <Directory>[];
  final packageRoot = _packageRoot(root);

  bool shouldExclude(Directory dir) {
    final rel = p.relative(
      p.normalize(dir.absolute.path),
      from: packageRoot,
    );
    final segments = p.split(rel).where((s) => s != '.').toList();
    if (segments.any((s) => s.startsWith('.'))) return true;
    // Only what sits above the first `lib` is outside the Dart sources.
    final lib = segments.indexOf('lib');
    final outside = lib == -1 ? segments : segments.sublist(0, lib);
    if (outside.any(_excludedOutsideLib.contains)) return true;
    return lib != -1 && segments.length > lib + 1 && segments[lib + 1] == 'gen';
  }

  void walk(Directory current) {
    if (shouldExclude(current)) return;

    try {
      final entities = current
          .listSync(recursive: false)
          .whereType<Directory>();
      for (final entity in entities) {
        walk(entity);
      }
    } catch (_) {}

    result.add(current);
  }

  walk(root);
  return result;
}

/// The directory exclusions are relative to: the nearest ancestor-or-self of
/// [target] holding a `pubspec.yaml`; failing that, the parent of a target
/// named `lib`, else the target itself.
String _packageRoot(Directory target) {
  final start = p.normalize(target.absolute.path);
  var dir = start;
  while (true) {
    if (File(p.join(dir, 'pubspec.yaml')).existsSync()) return dir;
    final parent = p.dirname(dir);
    if (parent == dir) break;
    dir = parent;
  }
  return p.basename(start) == 'lib' ? p.dirname(start) : start;
}

void _createOrUpdateBarrelForDir(Directory dir) {
  final dirName = _basename(dir.path);
  String barrelFileName;

  if (dirName == 'lib') {
    // Try to get package name from pubspec.yaml
    final pubspecFile = File(_join(dir.parent.path, 'pubspec.yaml'));
    if (pubspecFile.existsSync()) {
      final content = pubspecFile.readAsStringSync();
      final nameMatch = RegExp(
        r'^name:\s+([a-zA-Z0-9_]+)',
        multiLine: true,
      ).firstMatch(content);
      if (nameMatch != null) {
        barrelFileName = nameMatch.group(1)!;
      } else {
        stdout.writeln(
          '  [WARN] No package name found in pubspec.yaml',
        );
        return;
      }
    } else {
      // If no pubspec, skip lib (might not be a package root)
      return;
    }
  } else {
    barrelFileName = dirName;
  }

  final barrelFile = File(_join(dir.path, '$barrelFileName.dart'));
  final exports = <String>[];

  // 1. Get all .dart files in the directory (maxdepth 1)
  try {
    final entities = dir.listSync(recursive: false);
    for (final entity in entities) {
      if (entity is File && entity.path.endsWith('.dart')) {
        final filename = _basename(entity.path);
        if (filename == '$barrelFileName.dart' ||
            filename.endsWith('.g.dart') ||
            filename.endsWith('.freezed.dart') ||
            filename.endsWith('.mocks.dart') ||
            filename.endsWith('.test.dart') ||
            filename.endsWith('_test.dart') ||
            filename.startsWith('firebase_options')) {
          continue;
        }

        // Check if file has "part of"
        final content = entity.readAsStringSync();
        if (content.contains(RegExp(r'^part\s+of\s+', multiLine: true))) {
          stdout.writeln('  - Skipped (part of file): $filename');
          continue;
        }

        exports.add("export '$filename';");
      }
    }
  } catch (_) {}

  // 2. Get child directories containing their own barrel files
  try {
    final entities = dir.listSync(recursive: false).whereType<Directory>();
    for (final subdir in entities) {
      final subdirName = _basename(subdir.path);
      final childBarrel = File(_join(subdir.path, '$subdirName.dart'));
      if (childBarrel.existsSync()) {
        exports.add("export '$subdirName/$subdirName.dart';");
      }
    }
  } catch (_) {}

  if (exports.isEmpty && !barrelFile.existsSync()) {
    return;
  }

  exports.sort();

  final newExportLines = [
    '// Auto-generated exports, do not edit manually.',
    ...exports,
  ];

  if (!barrelFile.existsSync()) {
    if (exports.isNotEmpty) {
      barrelFile.writeAsStringSync('${newExportLines.join('\n')}\n');
      stdout.writeln('  -> Created barrel: ${barrelFile.path}');
    }
    return;
  }

  // Update existing barrel file
  stdout.writeln('  - Updating barrel: ${barrelFile.path}');
  final existingLines = barrelFile.readAsLinesSync();

  // Remove old exports and comment
  final cleanedLines = <String>[];
  for (final line in existingLines) {
    if (line.contains('Auto-generated exports, do not edit manually.')) {
      continue;
    }
    if (line.trim().startsWith("export '")) {
      continue;
    }
    cleanedLines.add(line);
  }

  // Find last import or library statement index
  var lastImportIdx = -1;
  for (var i = 0; i < cleanedLines.length; i++) {
    final trimmed = cleanedLines[i].trim();
    // `library;` (Dart 3's unnamed form) must anchor too, not just the legacy
    // `library some_name;`. Without it a barrel that opens with a doc comment
    // has no anchor, so the exports get prepended *above* that comment and the
    // file reads back-to-front — which is how the sample banners would end up
    // buried under the export block on the next run.
    if (trimmed.startsWith("import '") ||
        trimmed == 'library;' ||
        trimmed.startsWith('library ')) {
      lastImportIdx = i;
    }
  }

  final finalLines = <String>[];
  if (lastImportIdx == -1) {
    // Prepend
    if (exports.isNotEmpty) {
      finalLines.addAll(newExportLines);
      finalLines.add('');
    }
    finalLines.addAll(cleanedLines);
  } else {
    // Insert after last import
    for (var i = 0; i <= lastImportIdx; i++) {
      finalLines.add(cleanedLines[i]);
    }
    finalLines.add('');
    if (exports.isNotEmpty) {
      finalLines.addAll(newExportLines);
      finalLines.add('');
    }
    for (var i = lastImportIdx + 1; i < cleanedLines.length; i++) {
      finalLines.add(cleanedLines[i]);
    }
  }

  barrelFile.writeAsStringSync('${finalLines.join('\n')}\n');
  stdout.writeln('  -> Updated: ${barrelFile.path}');
}
