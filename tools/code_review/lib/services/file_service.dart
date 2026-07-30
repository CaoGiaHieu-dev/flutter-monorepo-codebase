import 'dart:io';
import '../utils/file_analyzer.dart';
import '../utils/git_helper.dart';

/// Service for handling file operations
class FileService {
  /// Read file content safely
  static Future<String?> readFileContent(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        return await file.readAsString();
      }
      return null;
    } catch (e) {
      // ignore: avoid_print
      print('Error reading file $filePath: $e');
      return null;
    }
  }

  /// Get files to review based on options
  static Future<List<String>> getFilesToReview({
    bool reviewAll = false,
    List<String> specificFiles = const [],
    String? folderPath,
    bool reviewChanged = false,
    bool reviewStaged = false,
    List<String> excludePatterns = const [],
  }) async {
    final files = <String>[];

    if (reviewAll) {
      files.addAll(await FileAnalyzer.getAllDartFiles());
    }

    if (specificFiles.isNotEmpty) {
      for (final file in specificFiles) {
        if (await File(file).exists()) {
          files.add(file);
        } else {
          // ignore: avoid_print
          print('⚠️  File not found: $file');
        }
      }
    }

    if (folderPath != null) {
      files.addAll(await FileAnalyzer.getDartFilesInFolder(folderPath));
    }

    if (reviewChanged) {
      files.addAll(await GitHelper.getChangedFiles());
    }

    if (reviewStaged) {
      files.addAll(await GitHelper.getStagedFiles());
    }

    // Remove duplicates and filter
    final uniqueFiles = files.toSet().toList();
    return FileAnalyzer.filterFiles(uniqueFiles, excludePatterns);
  }

  /// Read multiple files content
  static Future<Map<String, String>> readMultipleFiles(
    List<String> filePaths,
  ) async {
    final filesContent = <String, String>{};

    for (final filePath in filePaths) {
      final content = await readFileContent(filePath);
      if (content != null) {
        filesContent[filePath] = content;
      }
    }

    return filesContent;
  }

  /// Write content to file
  static Future<void> writeFile(String filePath, String content) async {
    try {
      final file = File(filePath);
      await file.parent.create(recursive: true);
      await file.writeAsString(content);
    } catch (e) {
      throw Exception('Failed to write file $filePath: $e');
    }
  }

  /// Check if file exists
  static Future<bool> fileExists(String filePath) async {
    return File(filePath).exists();
  }

  /// Create directory if it doesn't exist
  static Future<void> ensureDirectoryExists(String dirPath) async {
    final directory = Directory(dirPath);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
  }
}
