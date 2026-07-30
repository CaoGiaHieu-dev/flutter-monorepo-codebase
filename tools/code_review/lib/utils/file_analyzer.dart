import 'dart:io';
import 'package:path/path.dart' as path;
import '../core/enums.dart';

/// Utility class for analyzing file types and architecture layers
class FileAnalyzer {
  /// Get file type based on path and naming conventions
  static FileType getFileType(String filePath) {
    final fileName = path.basename(filePath);
    final dirPath = path.dirname(filePath);

    if (fileName.endsWith('_page.dart')) return FileType.page;
    if (fileName.endsWith('_widget.dart')) return FileType.widget;
    if (fileName.endsWith('_provider.dart')) return FileType.provider;
    if (fileName.endsWith('_entity.dart')) return FileType.entity;
    if (fileName.endsWith('_usecase.dart')) return FileType.useCase;
    if (fileName.endsWith('_repository.dart')) return FileType.repository;
    if (fileName.endsWith('_repository_impl.dart'))
      return FileType.repositoryImpl;
    if (fileName.endsWith('_data_source.dart')) return FileType.dataSource;
    if (fileName.contains('constants')) return FileType.constants;
    if (fileName.contains('config')) return FileType.config;
    if (dirPath.contains('models')) return FileType.model;
    if (dirPath.contains('params')) return FileType.parameters;

    return FileType.dartFile;
  }

  /// Get architecture layer based on file path
  static ArchitectureLayer getArchitectureLayer(String filePath) {
    if (filePath.startsWith('lib/presentation/'))
      return ArchitectureLayer.presentation;
    if (filePath.startsWith('lib/domain/')) return ArchitectureLayer.domain;
    if (filePath.startsWith('lib/data/')) return ArchitectureLayer.data;
    if (filePath.startsWith('lib/core/')) return ArchitectureLayer.core;
    if (filePath.startsWith('lib/gen/')) return ArchitectureLayer.generated;
    return ArchitectureLayer.unknown;
  }

  /// Check if file matches a pattern (supports * wildcard)
  static bool matchesPattern(String text, String pattern) {
    final regexPattern = pattern
        .replaceAll('**/', '.*/')
        .replaceAll('*', '[^/]*')
        .replaceAll('?', '.');
    return RegExp(regexPattern).hasMatch(text);
  }

  /// Validate that we're in a Flutter project
  static Future<bool> validateFlutterProject() async {
    final pubspecFile = File('pubspec.yaml');
    if (!await pubspecFile.exists()) {
      return false;
    }

    final libDir = Directory('lib');
    if (!await libDir.exists()) {
      return false;
    }

    // Check if pubspec.yaml contains Flutter dependencies
    final pubspecContent = await pubspecFile.readAsString();
    return pubspecContent.contains('flutter:') ||
        pubspecContent.contains('flutter_');
  }

  /// Get all Dart files in the project
  static Future<List<String>> getAllDartFiles() async {
    final files = <String>[];
    final libDir = Directory('lib');

    if (await libDir.exists()) {
      await for (final entity in libDir.list(recursive: true)) {
        if (entity is File && entity.path.endsWith('.dart')) {
          files.add(entity.path);
        }
      }
    }

    return files;
  }

  /// Get all Dart files in a specific folder
  static Future<List<String>> getDartFilesInFolder(String folderPath) async {
    final files = <String>[];
    final folder = Directory(folderPath);

    if (!await folder.exists()) {
      return files;
    }

    await for (final entity in folder.list(recursive: true)) {
      if (entity is File && entity.path.endsWith('.dart')) {
        files.add(entity.path);
      }
    }

    return files;
  }

  /// Filter files based on exclude patterns
  static List<String> filterFiles(
    List<String> files,
    List<String> excludePatterns,
  ) {
    if (excludePatterns.isEmpty) {
      // Default exclusions
      return files
          .where(
            (file) =>
                !file.contains('.g.dart') &&
                !file.contains('.freezed.dart') &&
                !file.contains('.mocks.dart') &&
                !file.contains('test/'),
          )
          .toList();
    }

    return files.where((file) {
      for (final pattern in excludePatterns) {
        if (matchesPattern(file, pattern)) {
          return false;
        }
      }
      return true;
    }).toList();
  }
}
