import 'dart:io';

const excludedDirs = {
  'lib/gen',
  '.git',
  '.dart_tool',
  'build',
  'ios',
  'android',
  'macos',
  'windows',
  'linux',
  'web',
  '.idea',
  '.vscode',
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
  final normalized = path.replaceAll('\\', '/');
  final parts = normalized.split('/');
  return parts.isEmpty ? '' : parts.last;
}

String _normalize(String path) {
  return path.replaceAll('\\', '/');
}

void main(List<String> args) {
  var targetDir = 'lib';
  if (args.isNotEmpty) {
    targetDir = args[0];
  }

  var dir = Directory(targetDir);
  while (!dir.existsSync()) {
    stderr.writeln('[ERROR] Thư mục "$targetDir" không tồn tại!');
    stdout.write(
      'Vui lòng nhập đường dẫn thư mục hợp lệ (hoặc "exit" để thoát): ',
    );
    final input = stdin.readLineSync();
    if (input == null || input.trim().toLowerCase() == 'exit') {
      exit(1);
    }
    targetDir = input.trim();
    dir = Directory(targetDir);
  }

  stdout.writeln(
    '\n[INFO] Bắt đầu tạo/cập nhật barrel files cho "$targetDir"...',
  );
  stdout.writeln(
    '[INFO] Quy tắc: Tự động sắp xếp, chèn export sau import, giữ lại logic tùy chỉnh.',
  );

  try {
    final allDirs = _getAllDirectories(dir);
    for (final subDir in allDirs) {
      _createOrUpdateBarrelForDir(subDir);
    }

    stdout.writeln('\n[INFO] Đang chạy format cho "$targetDir"...');
    final result = Process.runSync('dart', ['format', targetDir]);
    if (result.exitCode == 0) {
      stdout.write(result.stdout);
    } else {
      stderr.write(result.stderr);
    }

    stdout.writeln('\n[SUCCESS] Hoàn thành sinh barrel file!');
  } catch (e) {
    stderr.writeln('[ERROR] Đã xảy ra lỗi: $e');
    exit(1);
  }
}

List<Directory> _getAllDirectories(Directory root) {
  final result = <Directory>[];

  bool shouldExclude(String path) {
    final normalized = _normalize(path);
    for (final ex in excludedDirs) {
      if (normalized.contains('/$ex/') ||
          normalized.endsWith('/$ex') ||
          normalized == ex ||
          normalized.startsWith('$ex/')) {
        return true;
      }
    }
    return false;
  }

  void walk(Directory current) {
    if (shouldExclude(current.path)) return;

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
          '  [WARN] Không tìm thấy tên package trong pubspec.yaml',
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
          stdout.writeln('  - Bỏ qua (part of file): $filename');
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
      stdout.writeln('  -> Đã tạo file barrel mới: ${barrelFile.path}');
    }
    return;
  }

  // Update existing barrel file
  stdout.writeln('  - Cập nhật thông minh file: ${barrelFile.path}');
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
    if (trimmed.startsWith("import '") || trimmed.startsWith('library ')) {
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
  stdout.writeln('  -> Đã cập nhật thành công: ${barrelFile.path}');
}
